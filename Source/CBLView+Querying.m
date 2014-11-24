//
//  CBLView+Querying.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

extern "C" {
#import "CBLView+Internal.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLCollateJSON.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
}
#import <CBForest/CBForest.hh>
#import <CBForest/Tokenizer.hh>


using namespace forestdb;


@implementation CBLView (Querying)


BOOL CBLValueIsEntireDoc(NSData* valueData) {
    return valueData.length == 1 && *(uint8_t*)valueData.bytes == CollatableReader::kSpecial;
}


id CBLParseQueryValue(NSData* collatable) {
    CollatableReader reader((slice(collatable)));
    return reader.readNSObject();
}


#pragma mark - QUERYING:


/** Main internal call to query a view. */
- (CBLQueryIteratorBlock) _queryWithOptions: (CBLQueryOptions*)options
                                     status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    CBLQueryIteratorBlock iterator;
    if (options.fullTextQuery) {
        iterator = [self _fullTextQueryWithOptions: options status: outStatus];
    } else if ([self groupOrReduceWithOptions: options])
        iterator = [self _reducedQueryWithOptions: options status: outStatus];
    else
        iterator = [self _regularQueryWithOptions: options status: outStatus];
    LogTo(Query, @"Query %@: Returning iterator", _name);
    return iterator;
}


// Should this query be run as grouped/reduced?
- (BOOL) groupOrReduceWithOptions: (CBLQueryOptions*) options {
    if (options->group || options->groupLevel > 0)
        return YES;
    else if (options->reduceSpecified)
        return options->reduce;
    else
        return (self.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
}


- (CBLQueryIteratorBlock) _regularQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus
{
    if (!self.index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    __block IndexEnumerator e = [self _runForestQueryWithOptions: options];

    *outStatus = kCBLStatusOK;
    CBLDatabase* db = _weakDB;
    return ^CBLQueryRow*() {
        while (e.next()) {
            id docContents = nil;
            id key = e.key().readNSObject();
            id value = nil;
            NSString* docID = (NSString*)e.docID();
            SequenceNumber sequence = e.sequence();

            if (options->includeDocs) {
                NSDictionary* valueDict = nil;
                NSString* linkedID = nil;
                if (e.value().peekTag() == CollatableReader::kMap) {
                    value = e.value().readNSObject();
                    valueDict = $castIf(NSDictionary, value);
                    linkedID = valueDict.cbl_id;
                }
                if (linkedID) {
                    // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                    NSString* linkedRev = valueDict.cbl_rev; // usually nil
                    CBLStatus linkedStatus;
                    CBL_Revision* linked = [db getDocumentWithID: linkedID
                                                      revisionID: linkedRev
                                                         options: options->content
                                                          status: &linkedStatus];
                    docContents = linked ? linked.properties : $null;
                    sequence = linked.sequence;
                } else {
                    CBLStatus status;
                    CBL_Revision* rev = [db getDocumentWithID: docID revisionID: nil
                                                      options: options->content status: &status];
                    docContents = rev.properties;
                }
            }

            if (!value)
                value = e.value().data().copiedNSData();

            LogTo(QueryVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
                  _name, CBLJSONString(key), value, CBLJSONString(docID));
            auto row = [[CBLQueryRow alloc] initWithDocID: docID
                                                 sequence: sequence
                                                      key: key
                                                    value: value
                                            docProperties: docContents];
            if (CBLRowPassesFilter(db, row, options))
                return row;
        }
        return nil;
    };
}


#pragma mark - REDUCING/GROUPING:

#define PARSED_KEYS

// Are key1 and key2 grouped together at this groupLevel?
#ifdef PARSED_KEYS
static bool groupTogether(id key1, id key2, unsigned groupLevel) {
    if (groupLevel == 0)
        return [key1 isEqual: key2];
    if (![key1 isKindOfClass: [NSArray class]] || ![key2 isKindOfClass: [NSArray class]])
        return groupLevel == 1 && [key1 isEqual: key2];
    NSUInteger level = MIN(groupLevel, MIN([key1 count], [key2 count]));
    for (NSUInteger i = 0; i < level; i++) {
        if (![[key1 objectAtIndex: i] isEqual: [key2 objectAtIndex: i]])
            return NO;
    }
    return YES;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(id key, unsigned groupLevel) {
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}
#else
static bool groupTogether(NSData* key1, NSData* key2, unsigned groupLevel) {
    if (!key1 || !key2)
        return NO;
    if (groupLevel == 0)
        groupLevel = UINT_MAX;
    return CBLCollateJSONLimited(kCBLCollateJSON_Unicode,
                                (int)key1.length, key1.bytes,
                                (int)key2.length, key2.bytes,
                                groupLevel) == 0;
}

// Returns the prefix of the key to use in the result row, at this groupLevel
static id groupKey(NSData* keyJSON, unsigned groupLevel) {
    id key = fromJSON(keyJSON);
    if (groupLevel > 0 && [key isKindOfClass: [NSArray class]] && [key count] > groupLevel)
        return [key subarrayWithRange: NSMakeRange(0, groupLevel)];
    else
        return key;
}
#endif


// Invokes the reduce function on the parallel arrays of keys and values
static id callReduce(CBLReduceBlock reduceBlock, NSMutableArray* keys, NSMutableArray* values) {
    if (!reduceBlock)
        return nil;
    NSArray *lazyKeys, *lazyValues;
#ifdef PARSED_KEYS
    lazyKeys = keys;
#else
    keys = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: keys];
#endif
    lazyValues = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: values];
    @try {
        id result = reduceBlock(lazyKeys, lazyValues, NO);
        if (result)
            return result;
    } @catch (NSException *x) {
        MYReportException(x, @"reduce block");
    }
    return $null;
}


- (CBLQueryIteratorBlock) _reducedQueryWithOptions: (CBLQueryOptions*)options
                                            status: (CBLStatus*)outStatus
{
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;

    CBLReduceBlock reduce = self.reduceBlock;
    if (options->reduceSpecified) {
        if (!options->reduce) {
            reduce = nil;
        } else if (!reduce) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    }

    __block id lastKey = nil;
    CBLDatabase* db = _weakDB;
    NSMutableArray* keysToReduce = nil, *valuesToReduce = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }

    if (!self.index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    }
    __block IndexEnumerator e = [self _runForestQueryWithOptions: options];

    *outStatus = kCBLStatusOK;
    return ^CBLQueryRow*() {
        CBLQueryRow* row = nil;
        do {
            id key = e.next() ? e.key().readNSObject() : nil;
            if (lastKey && (!key || (group && !groupTogether(lastKey, key, groupLevel)))) {
                // key doesn't match lastKey; emit a grouped/reduced row for what came before:
                row = [[CBLQueryRow alloc] initWithDocID: nil
                                        sequence: 0
                                             key: (group ? groupKey(lastKey, groupLevel) : $null)
                                           value: callReduce(reduce, keysToReduce,valuesToReduce)
                                   docProperties: nil];
                LogTo(QueryVerbose, @"Query %@: Reduced row with key=%@, value=%@",
                                    _name, CBLJSONString(row.key), CBLJSONString(row.value));
                if (!CBLRowPassesFilter(db, row, options))
                    row = nil;
                [keysToReduce removeAllObjects];
                [valuesToReduce removeAllObjects];
            }

            if (key && reduce) {
                // Add this key/value to the list to be reduced:
                [keysToReduce addObject: key];
                CollatableReader collatableValue = e.value();
                id value;
                if (collatableValue.peekTag() == CollatableReader::kSpecial) {
                    CBLStatus status;
                    CBL_Revision* rev = [db getDocumentWithID: (NSString*)e.docID()
                                                     sequence: e.sequence()
                                                       status: &status];
                    if (rev)
                        Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
                    value = rev.properties;
                } else {
                    value = collatableValue.readNSObject();
                }
                [valuesToReduce addObject: (value ?: $null)];
                //TODO: Reduce the keys/values when there are too many; then rereduce at end
            }

            lastKey = key;
        } while (!row && lastKey);
        return row;
    };
}


#pragma mark - FULL-TEXT:


- (CBLQueryIteratorBlock) _fullTextQueryWithOptions: (CBLQueryOptions*)options
                                             status: (CBLStatus*)outStatus
{
    MapReduceIndex* index = self.index;
    if (!index) {
        *outStatus = kCBLStatusNotFound;
        return nil;
    } else if (index->indexType() != kCBLFullTextIndex) {
        *outStatus = kCBLStatusBadRequest;
        return nil;
    }

    // Tokenize the query string:
    LogTo(QueryVerbose, @"Full-text search for:");
    std::vector<std::string> queryTokens;
    std::vector<KeyRange> collatableKeys;
    Tokenizer tokenizer("en", true);
    for (TokenIterator i(tokenizer, nsstring_slice(options.fullTextQuery), true); i; ++i) {
        collatableKeys.push_back(Collatable(i.token()));
        queryTokens.push_back(i.token());
    }

    LogTo(QueryVerbose, @"Iterating index...");
    NSMutableDictionary* docRows = [[NSMutableDictionary alloc] init];
    *outStatus = kCBLStatusOK;
    DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
    for (IndexEnumerator e = IndexEnumerator(index, collatableKeys, forestOpts); e.next(); ) {
        NSString* docID = (NSString*)e.docID();
        CBLFullTextQueryRow* row = docRows[docID];
        if (!row) {
            row = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                    sequence: e.sequence()];
            docRows[docID] = row;
        }
        std::string token = (std::string)e.key().readString();
        auto term = std::find(queryTokens.begin(), queryTokens.end(), token) - queryTokens.begin();
        NSRange range;
        CollatableReader reader(e.value());
        reader.beginArray();
        range.location = (NSUInteger)reader.readDouble();
        range.length = (NSUInteger)reader.readDouble();
        [row addTerm: term atRange: range];
    };

    NSEnumerator* rowEnum = docRows.objectEnumerator;
    return ^CBLQueryRow*() {
        return rowEnum.nextObject;
    };
}



/** Starts a view query, returning a CBForest enumerator. */
- (IndexEnumerator) _runForestQueryWithOptions: (CBLQueryOptions*)options
{
    MapReduceIndex* index = self.index;
    Assert(index);
    DocEnumerator::Options forestOpts = DocEnumerator::Options::kDefault;
    forestOpts.skip = options->skip;
    if (options->limit > 0)
        forestOpts.limit = options->limit;
    forestOpts.descending = options->descending;
    forestOpts.inclusiveStart = options->inclusiveStart;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    if (options.keys) {
        std::vector<KeyRange> collatableKeys;
        for (id key in options.keys)
            collatableKeys.push_back(Collatable(key));
        return IndexEnumerator(index,
                               collatableKeys,
                               forestOpts);
    } else {
        id endKey = keyForPrefixMatch(options.endKey, options->prefixMatchLevel);
        return IndexEnumerator(index,
                               Collatable(options.startKey),
                               nsstring_slice(options.startKeyDocID),
                               Collatable(endKey),
                               nsstring_slice(options.endKeyDocID),
                               forestOpts);
    }
}


#pragma mark - UTILITIES:


// Changes a maxKey into one that also extends to any key it matches as a prefix.
static id keyForPrefixMatch(id key, unsigned depth) {
    if (depth < 1)
        return key;
    if ([key isKindOfClass: [NSString class]]) {
        // Kludge: prefix match a string by appending max possible character value to it
        return [key stringByAppendingString: @"\uffffffff"];
    } else if ([key isKindOfClass: [NSArray class]]) {
        NSMutableArray* nuKey = [key mutableCopy];
        if (depth == 1) {
            [nuKey addObject: @{}];
        } else {
            id lastObject = keyForPrefixMatch(nuKey.lastObject, depth-1);
            [nuKey replaceObjectAtIndex: nuKey.count-1 withObject: lastObject];
        }
        return nuKey;
    } else {
        return key;
    }
}


BOOL CBLRowPassesFilter(CBLDatabase* db, CBLQueryRow* row, const CBLQueryOptions* options) {
    NSPredicate* filter = options.filter;
    if (filter) {
        row.database = db; // temporary; this may not be the final database instance
        if (![filter evaluateWithObject: row]) {
            LogTo(QueryVerbose, @"   ... on 2nd thought, filter predicate skipped that row");
            return NO;
        }
        row.database = nil;
    }
    return YES;
}


// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    MapReduceIndex* index = self.index;
    if (!index)
        return nil;
    NSMutableArray* result = $marray();

    IndexEnumerator e = [self _runForestQueryWithOptions: [CBLQueryOptions new]];
    while (e.next()) {
        [result addObject: $dict({@"key", CBLJSONString(e.key().readNSObject())},
                                 {@"value", CBLJSONString(e.value().readNSObject())},
                                 {@"seq", @(e.sequence())})];
    }
    return result;
}
#endif


@end
