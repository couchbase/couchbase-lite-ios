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
        _database = [database retain];
        _view = [view retain];
        _limit = kDefaultTDQueryOptions.limit;  // this has a nonzero default (UINT_MAX)
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
    [_database release];
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
            endKeyDocID=_endKeyDocID, stale=_stale, sequences=_sequences,
            database=_database;


- (TouchLiveQuery*) asLiveQuery {
    return [[[TouchLiveQuery alloc] initWithQuery: self] autorelease];
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
    
    NSArray* rows;
    SequenceNumber lastSequence;
    if (_view) {
        TDStatus status = [_view updateIndex];
        if (TDStatusIsError(status))
            return nil;
        lastSequence = _view.lastSequenceIndexed;
        rows = [_view queryWithOptions: &options status: &status];
    } else {
        NSDictionary* result = [_database.tddb getAllDocs: &options];
        lastSequence = [[result objectForKey: @"update_seq"] longLongValue];
        rows = [result objectForKey: @"rows"];
    }
    
    if (rows)
        _lastSequence = lastSequence;
    return rows;
}


- (TouchQueryEnumerator*) rows {
    NSArray* rows = self.run;
    if (!rows)
        return nil;
    return [[[TouchQueryEnumerator alloc] initWithDatabase: _database rows: rows] autorelease];
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
    [_rows release];
    [super dealloc];
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
    return [[_rows copy] autorelease];
}


- (void) setRows:(TouchQueryEnumerator *)rows {
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
    TouchQueryEnumerator* rows = super.rows;
    if (rows && ![rows isEqual: _rows]) {
        Log(@"TDLiveQuery: ...Rows changed! (now %lu)", (unsigned long)rows.count);
        self.rows = rows;   // Triggers KVO notification
    }
}


@end




@implementation TouchQueryEnumerator


@synthesize totalCount=_totalCount, sequenceNumber=_sequenceNumber;


- (id) initWithDatabase: (TouchDatabase*)database
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
    if (![object isKindOfClass: [TouchQueryEnumerator class]])
        return NO;
    TouchQueryEnumerator* otherEnum = object;
    return [otherEnum->_rows isEqual: _rows];
}


- (NSUInteger) count {
    return _rows.count;
}


- (TouchQueryRow*) rowAtIndex: (NSUInteger)index {
    return [[[TouchQueryRow alloc] initWithDatabase: _database
                                             result: [_rows objectAtIndex:index]]
            autorelease];
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


- (TouchDocument*) document {
    NSString* docID = self.documentID;
    if (!docID)
        return nil;
    TouchDocument* doc = [_database documentWithID: docID];
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
