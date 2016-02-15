//
//  CBL_ForestDBQueryEnumerator.mm
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/11/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBL_ForestDBQueryEnumerator.h"
extern "C" {
#import "CBL_ForestDBStorage.h"
#import "CBL_ForestDBViewStorage.h"
#import "ExceptionUtils.h"
}
#import "CBLForestBridge.h"


@implementation CBL_ForestDBQueryEnumerator
{
    CBL_ForestDBViewStorage* _viewStorage;
    C4QueryEnumerator *_enum;
    unsigned _limit;
    unsigned _skip;
    BOOL _includeDocs, _geoQuery, _fullTextQuery, _group;
    CBLQueryRowFilter _filter;

    unsigned _groupLevel;
    id _lastKey;
    NSMutableArray* _keysToReduce, *_valuesToReduce;
    CBLReduceBlock _reduce;
}


- (instancetype) initWithStorage: (CBL_ForestDBViewStorage*)viewStorage
                          C4View: (C4View*)c4view
                         options: (CBLQueryOptions*)options
                           error: (C4Error*)outError
{
    self = [super initWithSequenceNumber: c4view_getLastSequenceChangedAt(c4view) rows: nil];
    if (self) {
        _viewStorage = viewStorage;
        _includeDocs = options->includeDocs;
        _geoQuery = (options->bbox != NULL);
        _fullTextQuery = (options.fullTextQuery != nil);
        _filter = options.filter;

        _groupLevel = options->groupLevel;
        _group = options->group || _groupLevel > 0;

        _reduce = _viewStorage.delegate.reduceBlock;
        if (options->reduceSpecified) {
            if (!options->reduce) {
                _reduce = nil;
            } else if (!_reduce) {
                Warn(@"Cannot use reduce option in view %@ which has no reduce block defined",
                     _viewStorage.name);
                *outError = {HTTPDomain, kC4HTTPBadRequest};
                return nil;
            }
        }
        if (_reduce) {
            _keysToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
            _valuesToReduce = [[NSMutableArray alloc] initWithCapacity: 100];
        }

        BOOL customSkipOrLimit = NO;
        if (_filter || _group || _reduce) {
            // #574: Custom post-filter (or group/reduce) means skip/limit apply to the filtered
            // rows, not to the underlying query, so handle them myself:
            customSkipOrLimit = YES;
            _limit = options->limit;
            _skip = options->skip;
        } else {
            _limit = UINT_MAX;
        }

        _enum = [self _createQueryWithOptions: options
                            customSkipOrLimit: customSkipOrLimit
                                       onView: c4view
                                        error: outError];
        if (!_enum)
            return nil;
    }
    return self;
}


/** Creates a C4QueryEnumerator. */
- (C4QueryEnumerator*) _createQueryWithOptions: (CBLQueryOptions*)options
                             customSkipOrLimit: (BOOL)customSkipOrLimit
                                        onView: (C4View*)_view
                                         error: (C4Error*)outError
{
    Assert(_view); // caller MUST call -openIndex: first

    id startKey = options.startKey, endKey = options.endKey;
    __strong id &maxKey = options->descending ? startKey : endKey;
    maxKey = CBLKeyForPrefixMatch(maxKey, options->prefixMatchLevel);
    CLEANUP(C4Key) *c4StartKey = id2key(startKey);
    CLEANUP(C4Key) *c4EndKey = id2key(endKey);

    C4QueryOptions forestOpts = kC4DefaultQueryOptions;
    if (!customSkipOrLimit) {
        forestOpts.skip = options->skip;
        if (options->limit != kCBLQueryOptionsDefaultLimit)
            forestOpts.limit = options->limit;
    }
    forestOpts.descending = options->descending;
    forestOpts.inclusiveStart = options->inclusiveStart;
    forestOpts.inclusiveEnd = options->inclusiveEnd;
    forestOpts.startKeyDocID = string2slice(options.startKeyDocID);
    forestOpts.endKeyDocID = string2slice(options.endKeyDocID);
    forestOpts.startKey = c4StartKey;
    forestOpts.endKey = c4EndKey;

    if (options->bbox) {
        return c4view_geoQuery(_view, geoRect2Area(*options->bbox), outError);
    } else if (options.fullTextQuery) {
        return c4view_fullTextQuery(_view, string2slice(options.fullTextQuery),
                                    kC4SliceNull, &forestOpts, outError);
    } else {
        if (options.keys) {
            forestOpts.keysCount = options.keys.count;
            forestOpts.keys = (const C4Key**)malloc(forestOpts.keysCount * sizeof(C4Key*));
            NSUInteger i = 0;
            for (id keyObj in options.keys) {
                forestOpts.keys[i++] = id2key(keyObj);
            }
        }

        C4QueryEnumerator *e = c4view_query(_view, &forestOpts, outError);

        // Clean up allocated keys on the way out:
        if (forestOpts.keys) {
            for (NSUInteger i = 0; i < forestOpts.keysCount; i++)
                c4key_free((C4Key*)forestOpts.keys[i]);
            free(forestOpts.keys);
        }

        return e;
    }
}


- (void)dealloc {
    c4queryenum_free(_enum);
}


- (void) freeEnum {
    c4queryenum_free(_enum);
    _enum = NULL;
}


// Here's the guts of the enumeration:
- (CBLQueryRow*) generateNextRow {
    if (_enum == nil)
        return nil;
    if (_limit-- == 0) {
        [self freeEnum];
        return nil;
    }

    if (_group || _reduce)
        return [self nextObjectReduced];    // Use group/reduce method instead

    C4Error c4err;
    while (c4queryenum_next(_enum, &c4err)) {
        CBL_Revision* docRevision = nil;
        id key = key2id(_enum->key);
        id value = nil;
        NSString* docID = slice2string(_enum->docID);
        SequenceNumber sequence = _enum->docSequence;

        if (_includeDocs) {
            NSDictionary* valueDict = nil;
            NSString* linkedID = nil;
            if (_enum->value.size > 0 && ((char*)_enum->value.buf)[0] == '{') {
                value = slice2jsonObject(_enum->value, 0);
                valueDict = $castIf(NSDictionary, value);
                linkedID = valueDict.cbl_id;
            }
            CBLStatus status;
            if (linkedID) {
                // Linked document: http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views#Linked_documents
                NSString* linkedRev = valueDict.cbl_rev; // usually nil
                docRevision = [_viewStorage.dbStorage getDocumentWithID: linkedID
                                                             revisionID: linkedRev
                                                   withBody: YES status: &status];
                if (docRevision)
                    sequence = docRevision.sequence;
                else
                    Warn(@"%@: Couldn't load linked doc %@ rev %@: status %d",
                         self, linkedID, linkedRev, status);
            } else {
                NSDictionary* body = [_viewStorage.dbStorage getBodyWithID: docID
                                                                  sequence: sequence
                                                                    status: &status];
                if (body)
                    docRevision = [CBL_Revision revisionWithProperties: body];
                else
                    Warn(@"%@: Couldn't load body of %@ (seq %lld): status %d",
                         self, docID, sequence, status);
            }
        }

        if (!value)
            value = slice2data(_enum->value);
        LogVerbose(Query, @"Query %@: Found row with key=%@, value=%@, id=%@",
                   _viewStorage.name, CBLJSONString(key), value, CBLJSONString(docID));
        
        // Create a CBLQueryRow:
        CBLQueryRow* row;
        if (_geoQuery) {
            row = [[CBLGeoQueryRow alloc] initWithDocID: docID
                                               sequence: sequence
                                            boundingBox: area2GeoRect(_enum->geoBBox)
                                            geoJSONData: slice2data(_enum->geoJSON)
                                                  value: value
                                            docRevision: docRevision];
        } else if (_fullTextQuery) {
            CBLFullTextQueryRow *ftrow;
            ftrow = [[CBLFullTextQueryRow alloc] initWithDocID: docID
                                                      sequence: _enum->docSequence
                                                    fullTextID: _enum->fullTextID
                                                         value: value];
            for (NSUInteger t = 0; t < _enum->fullTextTermCount; t++) {
                const C4FullTextTerm *term = &_enum->fullTextTerms[t];
                [ftrow addTerm: term->termIndex atRange: {term->start, term->length}];
            }
            row = ftrow;
        } else {
            row = [[CBLQueryRow alloc] initWithDocID: docID
                                            sequence: sequence
                                                 key: key
                                               value: value
                                         docRevision: docRevision];
        }
        if (_filter) {
            if (![self rowPassesFilter: row])
                continue;
            if (_skip > 0) {
                --_skip;
                continue;
            }
        }
        // Got a row to return!
        return row;
    }

    // End of enumeration:
    [self freeEnum];
    return nil;
}


// Grouped/reduced iteration:
- (id) nextObjectReduced {
    CBLQueryRow* row = nil;
    do {
        if (!_enum)
            return nil;
        id key = nil;
        C4Error c4err;
        if (c4queryenum_next(_enum, &c4err)) {
            key = key2id(_enum->key);
        } else {
            [self freeEnum];
            if (c4err.code)
                break;
        }

        if (_lastKey && (!key || (_group && !groupTogether(_lastKey, key, _groupLevel)))) {
            // key doesn't match lastKey; emit a grouped/reduced row for what came before:
            row = [[CBLQueryRow alloc] initWithDocID: nil
                                sequence: 0
                                     key: (_group ? groupKey(_lastKey, _groupLevel) : $null)
                                   value: (_reduce ? [self callReduce] : nil)
                             docRevision: nil];
            LogVerbose(Query, @"Query %@: Reduced row with key=%@, value=%@",
                       _viewStorage.name, CBLJSONString(row.key), CBLJSONString(row.value));
            if (_filter && ![self rowPassesFilter: row])
                row = nil;
            [_keysToReduce removeAllObjects];
            [_valuesToReduce removeAllObjects];
        }

        if (key && _reduce) {
            // Add this key/value to the list to be reduced:
            [_keysToReduce addObject: key];
            id value = nil;
            if (c4SliceEqual(_enum->value, kC4PlaceholderValue)) {
                CBLStatus status;
                value = [_viewStorage.dbStorage getBodyWithID: slice2string(_enum->docID)
                                                     sequence: _enum->docSequence
                                                       status: &status];
                if (!value)
                    Warn(@"%@: Couldn't load doc for row value: status %d", self, status);
            } else if (_enum->value.size > 0) {
                value = slice2jsonObject(_enum->value, CBLJSONReadingAllowFragments);
            }
            [_valuesToReduce addObject: (value ?: $null)];
            //TODO: Reduce the keys/values when there are too many; then rereduce at end
        }

        if (_skip > 0 && row) {
            --_skip;
            row = nil;
        }

        _lastKey = key;
    } while (!row && _lastKey);
    return row;
}


#pragma mark - UTILITY FUNCTIONS


- (BOOL) rowPassesFilter: (CBLQueryRow*)row {
    //FIX: I'm not supposed to know the delegates' real classes...
    [row moveToDatabase: _viewStorage.dbStorage.delegate view: _viewStorage.delegate];
    if (!_filter(row))
        return NO;
    [row _clearDatabase];
    return YES;
}


#define PARSED_KEYS

#ifdef PARSED_KEYS
// Are key1 and key2 grouped together at this groupLevel?
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
- (id) callReduce {
    NSArray *lazyKeys, *lazyValues;
#ifdef PARSED_KEYS
    lazyKeys = _keysToReduce;
#else
    keys = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: _keysToReduce];
#endif
    lazyValues = [[CBLLazyArrayOfJSON alloc] initWithMutableArray: _valuesToReduce];
    @try {
        id result = _reduce(lazyKeys, lazyValues, NO);
        if (result)
            return result;
    } @catch (NSException *x) {
        MYReportException(x, @"reduce block");
    }
    return $null;
}


@end
