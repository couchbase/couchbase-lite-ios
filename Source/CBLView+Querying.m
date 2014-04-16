//
//  CBLView+Internal.m
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

#import "CBLView+Internal.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLCollateJSON.h"
#import "CBLMisc.h"
#import <CBForest/CBForest.h>
#import "ExceptionUtils.h"


#define kReduceBatchSize 100


const CBLQueryOptions kDefaultCBLQueryOptions = {
    .limit = UINT_MAX,
    .inclusiveEnd = YES,
    .fullTextRanking = YES
    // everything else will default to nil/0/NO
};


static inline NSString* toJSONString( id object ) {
    if (!object)
        return nil;
    return [CBLJSON stringWithJSONObject: object
                                 options: CBLJSONWritingAllowFragments
                                   error: NULL];
}


@implementation CBLView (Querying)


#pragma mark - QUERYING:


typedef CBLStatus (^QueryRowBlock)(id key, id value, NSString* docID, SequenceNumber sequence);


/** Runs a view query, calling the onRow callback for each row. */
- (CBLStatus) _runQueryWithOptions: (const CBLQueryOptions*)options
                             onRow: (QueryRowBlock)onRow
{
    __block CBLStatus status = kCBLStatusOK;
    if (options->keys) {
        // If given keys, look up each key:
        for (id key in options->keys) {
            NSError* error;
            BOOL ok = [_index queryStartKey: key startDocID: nil
                                     endKey: key endDocID: nil
                                    options: NULL
                                      error: &error
                                      block: ^(id key, id value, NSString *docID, uint64_t sequence,
                                               BOOL *stop)
            {
               status = onRow(key, value, docID, sequence);
               *stop = CBLStatusIsError(status);
            }];
            if (!ok)
                status = kCBLStatusDBError;
            if (CBLStatusIsError(status))
                break;
        }

    } else {
        // Regular range query:
        CBForestEnumerationOptions forestOpts = {
            .skip = options->skip,
            .limit = options->limit,
            .descending = options->descending,
            .inclusiveEnd = options->inclusiveEnd,
        };
        __block CBLStatus status = kCBLStatusOK;
        NSError* error;
        BOOL ok = [_index queryStartKey: options->startKey
                             startDocID: options->startKeyDocID
                                 endKey: options->endKey
                               endDocID: options->endKeyDocID
                                options: &forestOpts
                                  error: &error
                                  block: ^(id key, id value, NSString *docID, uint64_t sequence,
                                           BOOL *stop)
        {
            status = onRow(key, value, docID, sequence);
            *stop = CBLStatusIsError(status);
        }];
        if (!ok)
            status = kCBLStatusDBError;
    }
    return status;
}


// Should this query be run as grouped/reduced?
- (BOOL) groupOrReduceWithOptions: (const CBLQueryOptions*) options {
    if (options->group || options->groupLevel > 0)
        return YES;
    else if (options->reduceSpecified)
        return options->reduce;
    else
        return (self.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
}


/** Main internal call to query a view. */
- (NSArray*) _queryWithOptions: (const CBLQueryOptions*)options
                        status: (CBLStatus*)outStatus
{
    if (!options)
        options = &kDefaultCBLQueryOptions;
    NSArray* rows;
    if (options->fullTextQuery) {
        Warn(@"Full-text querying is out of service at this time."); //FIX: Re-implement FTS
        *outStatus = kCBLStatusNotImplemented;
        return nil;
    } else if ([self groupOrReduceWithOptions: options])
        rows = [self _reducedQueryWithOptions: options status: outStatus];
    else
        rows = [self _regularQueryWithOptions: options status: outStatus];
    LogTo(View, @"Query %@: Returning %u rows", _name, (unsigned)rows.count);
    return rows;
}


- (NSArray*) _regularQueryWithOptions: (const CBLQueryOptions*)options
                               status: (CBLStatus*)outStatus
{
    CBLDatabase* db = _weakDB;
    NSMutableArray* rows = $marray();
    *outStatus = [self _runQueryWithOptions: options
                                      onRow: ^CBLStatus(id key, id value,
                                                        NSString* docID, SequenceNumber sequence)
    {
        id docContents = nil;
        if (options->includeDocs) {
            NSDictionary* valueDict = $castIf(NSDictionary, value);
            NSString* linkedID = valueDict.cbl_id;
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
        LogTo(ViewVerbose, @"Query %@: Found row with key=%@, value=%@, id=%@",
              _name, toJSONString(key), toJSONString(value), toJSONString(docID));
        CBLQueryRow* row = [[CBLQueryRow alloc] initWithDocID: docID
                                                     sequence: sequence
                                                          key: key
                                                        value: value
                                                docProperties: docContents];
        [rows addObject: row];
        return kCBLStatusOK;
    }];

    return rows;
}


#pragma mark - REDUCING/GROUPING:

#define PARSED_KEYS

// Are key1 and key2 grouped together at this groupLevel?
#ifdef PARSED_KEYS
static bool groupTogether(id key1, id key2, unsigned groupLevel) {
    if (groupLevel == 0)
        return [key1 isEqual: key2];
    if (![key1 isKindOfClass: [NSArray class]] || ![key2 isKindOfClass: [NSArray class]])
        return NO;
    NSUInteger level = MIN([key1 count], [key2 count]);
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
    CBLLazyArrayOfJSON* lazyKeys = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: keys];
    CBLLazyArrayOfJSON* lazyVals = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: values];
    @try {
        id result = reduceBlock(lazyKeys, lazyVals, NO);
        if (result)
            return result;
    } @catch (NSException *x) {
        MYReportException(x, @"reduce block");
    }
    return $null;
}


- (NSMutableArray*) _reducedQueryWithOptions: (const CBLQueryOptions*)options
                                      status: (CBLStatus*)outStatus
{
    unsigned groupLevel = options->groupLevel;
    bool group = options->group || groupLevel > 0;
    if (options->reduceSpecified) {
        if (options->reduce && !self.reduceBlock) {
            Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                 _name);
            *outStatus = kCBLStatusBadParam;
            return nil;
        }
    }

    CBLReduceBlock reduce = self.reduceBlock;
    NSMutableArray* keysToReduce = nil, *valuesToReduce = nil;
    if (reduce) {
        keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
    }
    __block id lastKey = nil;

    NSMutableArray* rows = $marray();
    *outStatus = [self _runQueryWithOptions: options
                                      onRow: ^CBLStatus(id key, id value,
                                                        NSString* docID, SequenceNumber sequence)
    {
        if (group && !groupTogether(key, lastKey, groupLevel)) {
            if (lastKey) {
                // This pair starts a new group, so reduce & record the last one:
                id key = groupKey(lastKey, groupLevel);
                id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
                [rows addObject: [[CBLQueryRow alloc] initWithDocID: nil
                                                           sequence: 0
                                                                key: key
                                                              value: reduced
                                                      docProperties: nil]];
                [keysToReduce removeAllObjects];
                [valuesToReduce removeAllObjects];
            }
            lastKey = [key copy];
        }
        LogTo(ViewVerbose, @"Query %@: Will reduce row with key=%@, value=%@",
              _name, toJSONString(key), toJSONString(value));
        [keysToReduce addObject: key];
        [valuesToReduce addObject: value ?: $null];
        return kCBLStatusOK;
    }];

    if (keysToReduce.count > 0) {
        // Finish the last group (or the entire list, if no grouping):
        id key = group ? groupKey(lastKey, groupLevel) : $null;
        id reduced = callReduce(reduce, keysToReduce, valuesToReduce);
        LogTo(ViewVerbose, @"Query %@: Reduced to key=%@, value=%@",
              _name, toJSONString(key), toJSONString(reduced));
        [rows addObject: [[CBLQueryRow alloc] initWithDocID: nil
                                                   sequence: 0
                                                        key: key
                                                      value: reduced
                                              docProperties: nil]];
    }
    return rows;
}


#pragma mark - OTHER:

// This is really just for unit tests & debugging
#if DEBUG
- (NSArray*) dump {
    if (!_index)
        return nil;
    NSMutableArray* result = $marray();
    [_index queryStartKey: nil startDocID: nil
                   endKey: nil endDocID: nil
                  options: NULL error: NULL
                    block: ^(id key, id value, NSString *docID, uint64_t sequence, BOOL *stop)
    {
        [result addObject: $dict({@"key", toJSONString(key)},
                                 {@"value", toJSONString(value)},
                                 {@"seq", @(sequence)})];
    }];
    return result;
}
#endif


@end
