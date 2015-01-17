//
//  CBLRouter+Changes.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/12/15.
//
//

#import "CBL_Router.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"


#define kMinHeartbeat 5.0


@implementation CBL_Router (Changes)


- (CBLStatus) do_GET_changes: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    
    [self parseChangesMode];
    // Regular poll is cacheable:
    if (_changesMode < kContinuousFeed)
        if ([self cacheWithEtag: $sprintf(@"%lld", _db.lastSequenceNumber)])
            return kCBLStatusNotModified;

    // Get options:
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    _changesIncludeDocs = [self boolQuery: @"include_docs"];
    _changesIncludeConflicts = $equal([self query: @"style"], @"all_docs");
    options.includeDocs = _changesIncludeDocs;
    options.includeConflicts = _changesIncludeConflicts;
    options.contentOptions = [self contentOptions];
    options.sortBySequence = !options.includeConflicts;
    options.limit = [self intQuery: @"limit" defaultValue: options.limit];
    int since = [[self query: @"since"] intValue];
    
    NSString* filterName = [self query: @"filter"];
    if (filterName) {
        CBLStatus status;
        _changesFilter = [_db compileFilterNamed: filterName status: &status];
        if (!_changesFilter)
            return status;
        _changesFilterParams = [self.queries copy];
        LogTo(CBL_Router, @"Filter params=%@", _changesFilterParams);
    }
    
    CBL_RevisionList* changes = [db changesSinceSequence: since
                                               options: &options
                                                filter: _changesFilter
                                                params: _changesFilterParams];
    if (!changes)
        return db.lastDbError;
    
    
    if ((_changesMode >= kContinuousFeed) || (_changesMode == kLongPollFeed && changes.count==0)) {
        // Response is going to stay open (continuous, or hanging GET):
        if (_changesMode == kEventSourceFeed)
            _response[@"Content-Type"] = @"text/event-stream; charset=utf-8";
        if (_changesMode >= kContinuousFeed) {
            [self sendResponseHeaders];
            for (CBL_Revision* rev in changes) 
                [self sendContinuousLine: [self changeDictForRev: rev]];
        }
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(dbChanged:)
                                                     name: CBL_DatabaseChangesNotification
                                                   object: db];

        NSString* heartbeatParam = [self query:@"heartbeat"];
        if (heartbeatParam) {
            NSTimeInterval heartbeat = [heartbeatParam doubleValue] / 1000.0;
            if (heartbeat <= 0)
                return kCBLStatusBadRequest;
            else if (heartbeat < kMinHeartbeat)
                heartbeat = kMinHeartbeat;
            NSString* heartbeatResponse = (_changesMode == kEventSourceFeed) ? @":\n\n" : @"\r\n";
            [self startHeartbeat: heartbeatResponse interval: heartbeat];
        }
        
        // Don't close connection; more data to come
        return 0;
    } else {
        // Return a response immediately and close the connection:
        if (_changesIncludeConflicts)
            _response.bodyObject = [self responseBodyForChangesWithConflicts: changes.allRevisions
                                                                       since: since
                                                                       limit: options.limit];
        else
            _response.bodyObject = [self responseBodyForChanges: changes.allRevisions since: since];
        return kCBLStatusOK;
    }
}


- (NSDictionary*) responseBodyForChanges: (NSArray*)changes since: (UInt64)since {
    NSArray* results = [changes my_map: ^(id rev) {return [self changeDictForRev: rev];}];
    if (changes.count > 0)
        since = [[changes lastObject] sequence];
    return $dict({@"results", results}, {@"last_seq", @(since)});
}


- (NSDictionary*) responseBodyForChangesWithConflicts: (NSArray*)changes
                                                since: (UInt64)since
                                                limit: (NSUInteger)limit
{
    // Assumes the changes are grouped by docID so that conflicts will be adjacent.
    NSMutableArray* entries = [NSMutableArray arrayWithCapacity: changes.count];
    NSString* lastDocID = nil;
    NSDictionary* lastEntry = nil;
    for (CBL_Revision* rev in changes) {
        NSString* docID = rev.docID;
        if ($equal(docID, lastDocID)) {
            [lastEntry[@"changes"] addObject: $dict({@"rev", rev.revID})];
        } else {
            lastEntry = [self changeDictForRev: rev];
            [entries addObject: lastEntry];
            lastDocID = docID;
        }
    }
    // After collecting revisions, sort by sequence:
    [entries sortUsingComparator: ^NSComparisonResult(id e1, id e2) {
        return CBLSequenceCompare([e1[@"seq"] longLongValue],
                                 [e2[@"seq"] longLongValue]);
    }];
    if (entries.count > limit)
        [entries removeObjectsInRange: NSMakeRange(limit, entries.count - limit)];
    id lastSeq = (entries.lastObject)[@"seq"] ?: @(since);
    return $dict({@"results", entries}, {@"last_seq", lastSeq});
}


- (NSDictionary*) changeDictForRev: (CBL_Revision*)rev {
    return $dict({@"seq", @(rev.sequence)},
                 {@"id",  rev.docID},
                 {@"changes", $marray($dict({@"rev", rev.revID}))},
                 {@"deleted", rev.deleted ? $true : nil},
                 {@"doc", (_changesIncludeDocs ? rev.properties : nil)});
}


- (void) dbChanged: (NSNotification*)n {
    // Prevent myself from being dealloced if my client finishes during the call (see issue #266)
    __unused id retainSelf = self;

    NSMutableArray* changes = $marray();
    for (CBLDatabaseChange* change in (n.userInfo)[@"changes"]) {
        CBL_Revision* rev = change.addedRevision;
        CBL_Revision* winningRev = change.winningRevision;

        if (!_changesIncludeConflicts) {
            if (!winningRev)
                continue;     // this change doesn't affect the winning rev ID, no need to send it
            else if (!$equal(winningRev, rev)) {
                // This rev made a _different_ rev current, so substitute that one.
                // We need to emit the current sequence # in the feed, so put it in the rev.
                // This isn't correct internally (this is an old rev so it has an older sequence)
                // but consumers of the _changes feed don't care about the internal state.
                CBL_MutableRevision* mRev = winningRev.mutableCopy;
                if (_changesIncludeDocs)
                    [_db loadRevisionBody: mRev options: 0];
                mRev.sequence = rev.sequence;
                rev = mRev;
            }
        }
        
        if (![_db runFilter: _changesFilter params: _changesFilterParams onRevision:rev])
            continue;

        if (_changesMode == kLongPollFeed) {
            [changes addObject: rev];
        } else {
            Log(@"CBL_Router: Sending continous change chunk");
            [self sendContinuousLine: [self changeDictForRev: rev]];
        }
    }

    if (_changesMode == kLongPollFeed && changes.count > 0) {
        Log(@"CBL_Router: Sending longpoll response");
        [self sendResponseHeaders];
        NSDictionary* body = [self responseBodyForChanges: changes since: 0];
        _response.body = [CBL_Body bodyWithProperties: body];
        [self sendResponseBodyAndFinish: YES];
    }

    retainSelf = nil;
}


@end
