//
//  CBLRouter+Changes.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/12/15.
//  Copyright (c) 2011-2015 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBL_Router.h"
#import "CBLDatabase.h"
#import "CouchbaseLitePrivate.h"
#import "CBLInternal.h"
#import "CBLMisc.h"


#if DEBUG
// Make this configurable for testing purposes
NSTimeInterval kMinHeartbeat = 5.0;
NSTimeInterval kDefaultChangesTimeout = 60.0;
#else
#define kMinHeartbeat 5.0
#define kDefaultChangesTimeout 60.0
#endif

@implementation CBL_Router (Changes)


- (CBLStatus) do_POST_changes: (CBLDatabase*)db {
    // Merge the properties from the JSON request body into the URL queries.
    // The values have to be converted to strings because _queries only has string values.
    NSMutableDictionary* queries = [self.queries mutableCopy] ?: [NSMutableDictionary new];
    NSDictionary* body = self.bodyAsDictionary;
    for (NSString* key in body) {
        id value = body[key];
        if (![value isKindOfClass: [NSString class]]) {
            value = [CBLJSON stringWithJSONObject: value
                                          options: CBLJSONWritingAllowFragments
                                            error: NULL];
        }
        queries[key] = value;
    }
    _queries = [queries copy];

    return [self doChanges: db];
}


- (CBLStatus) do_GET_changes: (CBLDatabase*)db {
    [self parseChangesMode];
    // Regular poll is cacheable:
    if (_changesMode < kContinuousFeed)
        if ([self cacheWithEtag: $sprintf(@"%lld", _db.lastSequenceNumber)])
            return kCBLStatusNotModified;
    return [self doChanges: db];
}


- (CBLStatus) doChanges: (CBLDatabase*)db {
    // http://docs.couchdb.org/en/latest/api/database/changes.html
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    // Get options:
    [self parseChangesMode];
    CBLChangesOptions options = kDefaultCBLChangesOptions;
    _changesIncludeDocs = [self boolQuery: @"include_docs"];
    _changesIncludeConflicts = $equal([self query: @"style"], @"all_docs");
    if (_changesIncludeDocs)
        _changesContentOptions = self.contentOptions;
    options.includeDocs = _changesIncludeDocs;
    options.includeConflicts = _changesIncludeConflicts;
    options.sortBySequence = !options.includeConflicts;

    BOOL descending = [self boolQuery: @"descending"] && options.sortBySequence;
    // valid option only when the mode is NormalFeed:
    if (descending && _changesMode != kNormalFeed)
        return kCBLStatusBadParam;
    options.descending = descending;

    options.limit = [self intQuery: @"limit" defaultValue: options.limit];
    _changesSince = [[self query: @"since"] intValue];
    
    NSString* filterName = [self query: @"filter"];
    if (filterName) {
        CBLStatus status;
        _changesFilter = [_db loadFilterNamed: filterName status: &status];
        if (!_changesFilter)
            return status;
        _changesFilterParams = [self.queries copy];
        LogTo(Router, @"Filter params=%@", _changesFilterParams);
    }
    
    CBLStatus status;
    CBL_RevisionList* changes = [db changesSinceSequence: _changesSince
                                                 options: &options
                                                  filter: _changesFilter
                                                  params: _changesFilterParams
                                                  status: &status];
    if (!changes)
        return status;
    
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
        
        // Timeout:
        NSString* timeoutParam = [self query: @"timeout"];
        if (timeoutParam) {
            _changesTimeout = [timeoutParam doubleValue] / 1000.0;
            if (_changesTimeout <= 0)
                return kCBLStatusBadRequest;
        } else
            _changesTimeout = 0;
            
        
        // Heartbeat:
        NSString* heartbeatParam = [self query: @"heartbeat"];
        if (heartbeatParam) {
            NSTimeInterval heartbeat = [heartbeatParam doubleValue] / 1000.0;
            if (heartbeat <= 0)
                return kCBLStatusBadRequest;
            else if (heartbeat < kMinHeartbeat)
                heartbeat = kMinHeartbeat;
            NSString* heartbeatResponse = (_changesMode == kEventSourceFeed) ? @":\n\n" : @"\r\n";
            [self startHeartbeat: heartbeatResponse interval: heartbeat];
        } else {
            // Apply default timeout when heartbeat is not specified:
            if (_changesTimeout == 0)
                _changesTimeout = kDefaultChangesTimeout;
        }
        
        if (_changesTimeout > 0)
            [self startTimeout];
        
        // Don't close connection; more data to come
        return 0;
    } else {
        // Return a response immediately and close the connection:
        if (_changesIncludeConflicts)
            _response.bodyObject = [self responseBodyForChangesWithConflicts: changes.allRevisions
                                                                       since: _changesSince
                                                                       limit: options.limit];
        else
            _response.bodyObject = [self responseBodyForChanges: changes.allRevisions
                                                          since: _changesSince];
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
            [lastEntry[@"changes"] addObject: $dict({@"rev", rev.revIDString})];
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
    if (_changesIncludeDocs) {
        CBLStatus status;
        CBL_Revision* rev2 = [self applyOptions: _changesContentOptions
                                     toRevision: rev status: &status];
        if (rev2) {
            rev2.sequence = rev.sequence;
            rev = rev2;
        }
    }
    return $dict({@"seq", @(rev.sequence)},
                 {@"id",  rev.docID},
                 {@"changes", $marray($dict({@"rev", rev.revIDString}))},
                 {@"deleted", rev.deleted ? $true : nil},
                 {@"doc", (_changesIncludeDocs ? rev.properties : nil)});
}


- (void) dbChanged: (NSNotification*)n {
    // Prevent myself from being dealloced if my client finishes during the call (see issue #266)
    __unused id retainSelf = self;
    
    [self stopTimeout];

    NSMutableArray* changes = $marray();
    for (CBLDatabaseChange* change in (n.userInfo)[@"changes"]) {
        CBL_Revision* rev = change.addedRevision;
        if (!rev)
            continue; // ignore purges
        CBL_RevID* winningRevID = change.winningRevisionID;

        if (!_changesIncludeConflicts) {
            if (!winningRevID)
                continue;     // this change doesn't affect the winning rev ID, no need to send it
            else if (!$equal(winningRevID, rev.revID)) {
                // This rev made a _different_ rev current, so substitute that one.
                // We need to emit the current sequence # in the feed, so put it in the rev.
                // This isn't correct internally (this is an old rev so it has an older sequence)
                // but consumers of the _changes feed don't care about the internal state.
                CBLStatus status;
                CBL_Revision* mRev = [_db getDocumentWithID: rev.docID
                                                 revisionID: winningRevID
                                                   withBody: _changesIncludeDocs
                                                     status: &status];
                mRev.sequence = rev.sequence;
                rev = mRev;
            }
        }
        
        if (![_db runFilter: _changesFilter params: _changesFilterParams onRevision:rev])
            continue;

        if (_changesMode == kLongPollFeed) {
            [changes addObject: rev];
        } else {
            [self sendContinuousLine: [self changeDictForRev: rev]];
        }
        _changesSince = rev.sequence;
    }

    if (_changesMode == kLongPollFeed && changes.count > 0)
        [self sendLongpollResponseForChanges: changes since: 0];
    else
        [self startTimeout];

    retainSelf = nil;
}


- (void)sendLongpollResponseForChanges: (NSArray*)changes since: (UInt64)since {
    Log(@"CBL_Router: Sending longpoll response");
    [self sendResponseHeaders];
    NSDictionary* body = [self responseBodyForChanges: changes since: since];
    _response.body = [CBL_Body bodyWithProperties: body];
    [self sendResponseBodyAndFinish: YES];
}


- (void) startTimeout {
    assert(_changesTimeout > 0);
    [_changesTimeoutTimer invalidate];
    CBL_Router* weakSelf = self;
    _changesTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval: _changesTimeout
                                                           repeats: NO block: ^(NSTimer *timer) {
        CBL_Router* strongSelf = weakSelf;
        if (_changesMode == kLongPollFeed) {
            [strongSelf sendLongpollResponseForChanges: @[] since: _changesSince];
        } else {
            [strongSelf sendContinuousLine: $dict({@"last_seq", @(_changesSince)})];
            [strongSelf finished];
        }
    }];
}


- (void) stopTimeout {
    [_changesTimeoutTimer invalidate];
    _changesTimeoutTimer = nil;
}

@end
