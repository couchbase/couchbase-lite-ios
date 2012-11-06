//
//  TDQuery.m
//  TouchDB
//
//  Created by Jens Alfke on 6/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDBPrivate.h"
#import "TDView.h"


@interface TouchQueryEnumerator ()
- (id) initWithDatabase: (TouchDatabase*)db rows: (NSArray*)rows;
@end


@interface TouchQueryRow ()
- (id) initWithDatabase: (TouchDatabase*)db result: (id)result;
@end



@implementation TouchQuery


// A nil view refers to 'all documents'
- (id) initWithDatabase: (TouchDatabase*)database view: (TDView*)view {
    self = [super init];
    if (self) {
        _database = database;
        _view = view;
        _limit = kDefaultTDQueryOptions.limit;  // this has a nonzero default (UINT_MAX)
    }
    return self;
}


- (id)initWithDatabase: (TouchDatabase*)database mapBlock: (TDMapBlock)mapBlock {
    TDView* view = [database.tddb makeAnonymousView];
    if (self = [self initWithDatabase: database view: view]) {
        _temporaryView = YES;
        [view setMapBlock: mapBlock reduceBlock: nil version: @""];
    }
    return self;
}


- (id) initWithQuery: (TouchQuery*)query {
    self = [self initWithDatabase: query->_database view: query->_view];
    if (self) {
        _limit = query.limit;
        _skip = query.skip;
        self.startKey = query.startKey;
        self.endKey = query.endKey;
        _descending = query.descending;
        _prefetch = query.prefetch;
        self.keys = query.keys;
        _groupLevel = query.groupLevel;
        self.startKeyDocID = query.startKeyDocID;
        self.endKeyDocID = query.endKeyDocID;
        _stale = query.stale;
        
    }
    return self;
}


- (void) dealloc
{
    if (_temporaryView)
        [_view deleteView];
}


@synthesize  limit=_limit, skip=_skip, descending=_descending, startKey=_startKey, endKey=_endKey,
            prefetch=_prefetch, keys=_keys, groupLevel=_groupLevel, startKeyDocID=_startKeyDocID,
            endKeyDocID=_endKeyDocID, stale=_stale, sequences=_sequences,
            database=_database;


- (TouchLiveQuery*) asLiveQuery {
    return [[TouchLiveQuery alloc] initWithQuery: self];
}


- (NSArray*) run {
    TDQueryOptions options = {
        .startKey = _startKey,
        .endKey = _endKey,
        .keys = _keys,
        .skip = (unsigned)_skip,
        .limit = (unsigned)_limit,
        .groupLevel = (unsigned)_groupLevel,
        .descending = _descending,
        .includeDocs = _prefetch,
        .updateSeq = YES,
        .localSeq = _sequences,
        .inclusiveEnd = YES,
    };
    
    NSArray* rows;
    SequenceNumber lastSequence;
    if (_view) {
        lastSequence = _view.lastSequenceIndexed;
        if (_stale == kTDStaleNever || lastSequence <= 0) {
            _status = [_view updateIndex];
            if (TDStatusIsError(_status)) {
                Warn(@"Failed to update view index: %d", _status);
                return nil;
            }
            lastSequence = _view.lastSequenceIndexed;
        }
        rows = [_view queryWithOptions: &options status: &_status];
        // TODO: Implement kTDStaleUpdateAfter
        
    } else {
        NSDictionary* result = [_database.tddb getAllDocs: &options];
        _status = result ? kTDStatusOK :kTDStatusDBError; //FIX: getALlDocs should return status
        lastSequence = [result[@"update_seq"] longLongValue];
        rows = result[@"rows"];
    }
    
    if (rows)
        _lastSequence = lastSequence;
    return rows;
}


- (NSError*) error {
    return TDStatusIsError(_status) ? TDStatusToNSError(_status, nil) : nil;
}


- (TouchQueryEnumerator*) rows {
    NSArray* rows = self.run;
    if (!rows)
        return nil;
    return [[TouchQueryEnumerator alloc] initWithDatabase: _database rows: rows];
}


- (TouchQueryEnumerator*) rowsIfChanged {
    if (_database.tddb.lastSequence == _lastSequence)
        return nil;
    return self.rows;
}


@end




@implementation TouchLiveQuery

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}


- (TouchQueryEnumerator*) rows {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged)
                                                     name: kTouchDatabaseChangeNotification 
                                                   object: self.database];
    }
    if (!_rows) {
        _rows = [super.rows copy];
        Log(@"TDLiveQuery: Initial row count is %lu", (unsigned long)_rows.count);
    }
    // Have to return a copy because the enumeration has to start at item #0 every time
    return [_rows copy];
}


- (void) setRows:(TouchQueryEnumerator *)rows {
    _rows = rows;
}


- (void) databaseChanged {
    if (!_updating) {
        _updating = YES;
        [self performSelector: @selector(update) withObject: nil afterDelay: 0.0];
    }
}


- (void) update {
    _updating = NO;
    TouchQueryEnumerator* rows = super.rows;
    if (rows && ![rows isEqual: _rows]) {
        Log(@"TDLiveQuery: ...Rows changed! (now %lu)", (unsigned long)rows.count);
        self.rows = rows;   // Triggers KVO notification
    }
}


@end




@implementation TouchQueryEnumerator


@synthesize sequenceNumber=_sequenceNumber;


- (id) initWithDatabase: (TouchDatabase*)database
                   rows: (NSArray*)rows
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        if (!rows)
            return nil;
        _database = database;
        _rows = rows;
    }
    return self;
}


- (id) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithDatabase: _database
                                             rows: _rows];
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [TouchQueryEnumerator class]])
        return NO;
    TouchQueryEnumerator* otherEnum = object;
    return [otherEnum->_rows isEqual: _rows];
}


- (NSUInteger) count {
    return _rows.count;
}


- (TouchQueryRow*) rowAtIndex: (NSUInteger)index {
    return [[TouchQueryRow alloc] initWithDatabase: _database result: _rows[index]];
}


- (TouchQueryRow*) nextRow {
    if (_nextRow >= _rows.count)
        return nil;
    return [self rowAtIndex:_nextRow++];
}


- (id) nextObject {
    return [self nextRow];
}


@end




@implementation TouchQueryRow


- (id) initWithDatabase: (TouchDatabase*)database result: (id)result {
    self = [super init];
    if (self) {
        if (![result isKindOfClass: [NSDictionary class]]) {
            Warn(@"Unexpected row value in view results: %@", result);
            return nil;
        }
        _database = database;
        _result = result;
    }
    return self;
}


- (id) key                              {return _result[@"key"];}
- (id) value                            {return _result[@"value"];}
- (NSString*) sourceDocumentID          {return _result[@"id"];}
- (NSDictionary*) documentProperties    {return _result[@"doc"];}

- (NSString*) documentID {
    NSString* docID = _result[@"doc"][@"_id"];
    if (!docID)
        docID = _result[@"id"];
    return docID;
}

- (NSString*) documentRevision {
    // Get the revision id from either the embedded document contents,
    // or the '_rev' or 'rev' value key:
    NSString* rev = _result[@"doc"][@"_rev"];
    if (!rev) {
        id value = self.value;
        if ([value isKindOfClass: [NSDictionary class]]) {      // $castIf would log a warning
            rev = value[@"_rev"];
            if (!rev)
                rev = value[@"rev"];
        }
    }
    
    if (![rev isKindOfClass: [NSString class]])                 // $castIf would log a warning
        rev = nil;
    return rev;
}


- (id) keyAtIndex: (NSUInteger)index {
    id key = _result[@"key"];
    if ([key isKindOfClass:[NSArray class]])
        return (index < [key count]) ? key[index] : nil;
    else
        return (index == 0) ? key : nil;
}

- (id) key0                         {return [self keyAtIndex: 0];}
- (id) key1                         {return [self keyAtIndex: 1];}
- (id) key2                         {return [self keyAtIndex: 2];}
- (id) key3                         {return [self keyAtIndex: 3];}


- (TouchDocument*) document {
    NSString* docID = self.documentID;
    if (!docID)
        return nil;
    TouchDocument* doc = [_database documentWithID: docID];
    [doc loadCurrentRevisionFrom: self];
    return doc;
}


- (UInt64) localSequence {
    id seq = (self.documentProperties)[@"_local_seq"];
    return $castIf(NSNumber, seq).unsignedLongLongValue;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[key=%@; value=%@; id=%@]",
            [self class],
            [TDJSON stringWithJSONObject: self.key options: TDJSONWritingAllowFragments error: nil],
            [TDJSON stringWithJSONObject: self.value options: TDJSONWritingAllowFragments error: nil],
            self.documentID];
}


@end
