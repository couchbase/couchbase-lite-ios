//
//  TDQuery.m
//  TouchDB
//
//  Created by Jens Alfke on 6/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDQuery.h"
#import "TDDatabase+Documents.h"
#import "TDView.h"
#import "TDDocument.h"


@interface TDQueryEnumerator ()
- (id) initWithDatabase: (TDDatabase*)db rows: (NSArray*)rows;
@end


@interface TDQueryRow ()
- (id) initWithDatabase: (TDDatabase*)db result: (id)result;
@end



@implementation TDQuery


- (id) initWithView: (TDView*)view {
    NSParameterAssert(view);
    self = [super init];
    if (self) {
        _view = [view retain];
        _limit = kDefaultTDQueryOptions.limit;  // this has a nonzero default (UINT_MAX)
    }
    return self;
}


- (id) initWithQuery: (TDQuery*)query {
    self = [self initWithView: query->_view];
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
    [_view release];
    [_startKey release];
    [_endKey release];
    [_startKeyDocID release];
    [_endKeyDocID release];
    [_keys release];
    [super dealloc];
}


@synthesize  limit=_limit, skip=_skip, descending=_descending, startKey=_startKey, endKey=_endKey,
            prefetch=_prefetch, keys=_keys, groupLevel=_groupLevel, startKeyDocID=_startKeyDocID,
            endKeyDocID=_endKeyDocID, stale=_stale, sequences=_sequences;

- (TDDatabase*) database {
    return _view.database;
}


- (TDLiveQuery*) asLiveQuery {
    return [[[TDLiveQuery alloc] initWithQuery: self] autorelease];
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
        .inclusiveEnd = YES,
    };
    
    TDStatus status = [_view updateIndex];
    if (TDStatusIsError(status))
        return nil;
    SequenceNumber lastSequence = _view.lastSequenceIndexed;
    NSArray* rows = [_view queryWithOptions: &options status: &status];
    if (rows)
        _lastSequence = lastSequence;
    return rows;
}


- (TDQueryEnumerator*) rows {
    NSArray* rows = self.run;
    if (!rows)
        return nil;
    return [[[TDQueryEnumerator alloc] initWithDatabase: _view.database rows: rows] autorelease];
}


- (TDQueryEnumerator*) rowsIfChanged {
    if (_view.database.lastSequence == _lastSequence)
        return nil;
    return self.rows;
}


@end




@implementation TDLiveQuery

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_rows release];
    [super dealloc];
}


- (TDQueryEnumerator*) rows {
    if (!_observing) {
        _observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(databaseChanged)
                                                     name: TDDatabaseChangeNotification 
                                                   object: self.database];
    }
    if (!_rows)
        _rows = [super.rows copy];
    // Have to return a copy because the enumeration has to start at item #0 every time
    return [[_rows copy] autorelease];
}


- (void) setRows:(TDQueryEnumerator *)rows {
    [_rows autorelease];
    _rows = [rows retain];
}


- (void) databaseChanged {
    if (!_updating) {
        _updating = YES;
        [self performSelector: @selector(update) withObject: nil afterDelay: 0.0];
    }
}


- (void) update {
    _updating = NO;
    TDQueryEnumerator* rows = super.rows;
    if (rows && ![rows isEqual: _rows]) {
        Log(@"TDLiveQuery: ...Rows changed! (now %lu)", (unsigned long)rows.count);
        self.rows = rows;   // Triggers KVO notification
    }
}


@end




@implementation TDQueryEnumerator


@synthesize totalCount=_totalCount, sequenceNumber=_sequenceNumber;


- (id) initWithDatabase: (TDDatabase*)database
                   rows: (NSArray*)rows
{
    NSParameterAssert(database);
    self = [super init];
    if (self ) {
        if (!rows) {
            [self release];
            return nil;
        }
        _database = database;
        _rows = [rows retain];
    }
    return self;
}


- (id) copyWithZone: (NSZone*)zone {
    return [[[self class] alloc] initWithDatabase: _database
                                             rows: _rows];
}


- (void) dealloc
{
    [_rows release];
    [super dealloc];
}


- (BOOL) isEqual:(id)object {
    if (object == self)
        return YES;
    if (![object isKindOfClass: [TDQueryEnumerator class]])
        return NO;
    TDQueryEnumerator* otherEnum = object;
    return [otherEnum->_rows isEqual: _rows];
}


- (NSUInteger) count {
    return _rows.count;
}


- (TDQueryRow*) rowAtIndex: (NSUInteger)index {
    return [[[TDQueryRow alloc] initWithDatabase: _database
                                             result: [_rows objectAtIndex:index]]
            autorelease];
}


- (TDQueryRow*) nextRow {
    if (_nextRow >= _rows.count)
        return nil;
    return [self rowAtIndex:_nextRow++];
}


- (id) nextObject {
    return [self nextRow];
}


@end




@implementation TDQueryRow


- (id) initWithDatabase: (TDDatabase*)database result: (id)result {
    self = [super init];
    if (self) {
        if (![result isKindOfClass: [NSDictionary class]]) {
            Warn(@"Unexpected row value in view results: %@", result);
            [self release];
            return nil;
        }
        _database = database;
        _result = [result retain];
    }
    return self;
}


- (void)dealloc {
    [_result release];
    [super dealloc];
}


- (id) key                              {return [_result objectForKey: @"key"];}
- (id) value                            {return [_result objectForKey: @"value"];}
- (NSString*) sourceDocumentID          {return [_result objectForKey: @"id"];}
- (NSDictionary*) documentProperties    {return [_result objectForKey: @"doc"];}

- (NSString*) documentID {
    NSString* docID = [[_result objectForKey: @"doc"] objectForKey: @"_id"];
    if (!docID)
        docID = [_result objectForKey: @"id"];
    return docID;
}

- (NSString*) documentRevision {
    // Get the revision id from either the embedded document contents,
    // or the '_rev' or 'rev' value key:
    NSString* rev = [[_result objectForKey: @"doc"] objectForKey: @"_rev"];
    if (!rev) {
        id value = self.value;
        if ([value isKindOfClass: [NSDictionary class]]) {      // $castIf would log a warning
            rev = [value objectForKey: @"_rev"];
            if (!rev)
                rev = [value objectForKey: @"rev"];
        }
    }
    
    if (![rev isKindOfClass: [NSString class]])                 // $castIf would log a warning
        rev = nil;
    return rev;
}


- (id) keyAtIndex: (NSUInteger)index {
    id key = [_result objectForKey: @"key"];
    if ([key isKindOfClass:[NSArray class]])
        return (index < [key count]) ? [key objectAtIndex: index] : nil;
    else
        return (index == 0) ? key : nil;
}

- (id) key0                         {return [self keyAtIndex: 0];}
- (id) key1                         {return [self keyAtIndex: 1];}
- (id) key2                         {return [self keyAtIndex: 2];}
- (id) key3                         {return [self keyAtIndex: 3];}


- (TDDocument*) document {
    NSString* docID = self.documentID;
    if (!docID)
        return nil;
    TDDocument* doc = [_database documentWithID: docID];
    [doc loadCurrentRevisionFrom: self];
    return doc;
}


- (UInt64) localSequence {
    id seq = [self.documentProperties objectForKey: @"_local_seq"];
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
