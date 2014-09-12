//
//  CBL_Router+Handlers.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/5/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
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
#import "CBLDatabase+Attachments.h"
#import "CBLDatabase+Insertion.h"
#import "CBLDatabase+LocalDocs.h"
#import "CBLDatabase+Replication.h"
#import "CBLView+Internal.h"
#import "CBL_Body.h"
#import "CBLMultipartDocumentReader.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBL_Server.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "CBL_Replicator.h"
#import "CBL_Pusher.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBLJSON.h"

#import "CollectionUtils.h"
#import "Test.h"


@implementation CBL_Router (Handlers)


- (void) setResponseLocation: (NSURL*)url {
    // Strip anything after the URL's path (i.e. the query string)
    _response[@"Location"] = CBLURLWithoutQuery(url).absoluteString;
}


#pragma mark - SERVER REQUESTS:


- (CBLStatus) do_GETRoot {
    NSDictionary* info = @{@"couchdb": @"Welcome",        // for compatibility
                           @"CouchbaseLite": @"Welcome",
                           @"version": CBLVersion(),
                           @"vendor": @{@"name": @"Couchbase Lite (Objective-C)",
                                        @"version": CBLVersion()}
                           };
    _response.body = [CBL_Body bodyWithProperties: info];
    return kCBLStatusOK;
}


- (CBLStatus) do_GET_all_dbs {
    NSArray* dbs = _dbManager.allDatabaseNames ?: @[];
    _response.body = [[CBL_Body alloc] initWithArray: dbs];
    return kCBLStatusOK;
}


- (CBLStatus) do_POST_persona_assertion {
    NSDictionary* body = self.bodyAsDictionary;
    NSString* email = [CBLPersonaAuthorizer registerAssertion: body[@"assertion"]];
    if (email != nil) {
        _response.bodyObject = $dict({@"ok", @"registered"}, {@"email", email});
        return kCBLStatusOK;
    } else {
        _response.bodyObject = $dict({@"error", @"invalid assertion"});
        return kCBLStatusBadParam;
    }
}

- (CBLStatus) do_POST_facebook_token {
    NSDictionary* body = self.bodyAsDictionary;
    NSString* email = $castIf(NSString, body[@"email"]);
    NSString* remote_url = $castIf(NSString, body[@"remote_url"]);
    NSString* access_token = $castIf(NSString, body[@"access_token"]);
    if (email && access_token && remote_url) {
        NSURL* site_url = [NSURL URLWithString: remote_url];
        if (!site_url) {
            _response.bodyObject = $dict({@"error", @"invalid remote_url"});
            return kCBLStatusBadParam;
        }
        if (![CBLFacebookAuthorizer registerToken: access_token forEmailAddress: email forSite: site_url]) {
            _response.bodyObject = $dict({@"error", @"invalid access_token"});
            return kCBLStatusBadParam;
        } else {
            _response.bodyObject = $dict({@"ok", @"registered"}, {@"email", body[@"email"]});
            return kCBLStatusOK;
        }
    } else {
        _response.bodyObject = $dict({@"error", @"required fields: access_token, email, remote_url"});
        return kCBLStatusBadParam;
    }
}

- (CBLStatus) do_GET_uuids {
    int count = MIN(1000, [self intQuery: @"count" defaultValue: 1]);
    NSMutableArray* uuids = [NSMutableArray arrayWithCapacity: count];
    for (int i=0; i<count; i++)
        [uuids addObject: [CBLDatabase generateDocumentID]];
    _response.bodyObject = $dict({@"uuids", uuids});
    return kCBLStatusOK;
}


- (CBLStatus) do_GET_session {
    // Even though CouchbaseLite doesn't support user logins, it implements a generic response to the
    // CouchDB _session API, so that apps that call it (such as Futon!) won't barf.
    _response.bodyObject = $dict({@"ok", $true},
                                 {@"userCtx", $dict({@"name", $null},
                                                    {@"roles", @[@"_admin"]})});
    return kCBLStatusOK;
}


#pragma mark - DATABASE REQUESTS:


- (CBLStatus) do_GET: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Database_Information
    CBLStatus status = [self openDB];
    if (CBLStatusIsError(status))
        return status;
    NSUInteger num_docs = db.documentCount;
    SequenceNumber update_seq = db.lastSequenceNumber;
    if (num_docs == NSNotFound || update_seq == NSNotFound)
        return db.lastDbError;
    UInt64 startTime = round(db.startTime.timeIntervalSince1970 * 1.0e6); // it's in microseconds
    _response.bodyObject = $dict({@"db_name", db.name},
                                 {@"db_uuid", db.publicUUID},
                                 {@"doc_count", @(num_docs)},
                                 {@"update_seq", @(update_seq)},
                                 {@"committed_update_seq", @(update_seq)},
                                 {@"purge_seq", @(0)}, // TODO: Implement
                                 {@"disk_size", @(db.totalDataSize)},
                                 {@"instance_start_time", @(startTime)},
                                 {@"disk_format_version", @(db.schemaVersion)});
    return kCBLStatusOK;
}


- (CBLStatus) do_PUT: (CBLDatabase*)db {
    if (db.exists)
        return kCBLStatusDuplicate;
    NSError* error;
    if (![db open: &error])
        return CBLStatusFromNSError(error, db.lastDbError);
    [self setResponseLocation: _request.URL];
    return kCBLStatusCreated;
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db {
    if ([self query: @"rev"])
        return kCBLStatusBadID;  // CouchDB checks for this; probably meant to be a document deletion
    return [db deleteDatabase: NULL] ? kCBLStatusOK : kCBLStatusNotFound;
}


- (CBLStatus) do_POST_purge: (CBLDatabase*)db {
    // <http://wiki.apache.org/couchdb/Purge_Documents>
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kCBLStatusBadJSON;
    NSDictionary* purgedDocs;
    CBLStatus status = [db purgeRevisions: body result: &purgedDocs];
    if (CBLStatusIsError(status))
        return status;
    _response.bodyObject = $dict({@"purged", purgedDocs});
    return status;
}


- (CBLStatus) do_GET_all_docs: (CBLDatabase*)db {
    if ([self cacheWithEtag: $sprintf(@"%lld", db.lastSequenceNumber)])
        return kCBLStatusNotModified;
    
    CBLQueryOptions *options = [self getQueryOptions];
    if (!options)
        return kCBLStatusBadParam;
    return [self doAllDocs: options];
}

- (CBLStatus) do_POST_all_docs: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    CBLQueryOptions *options = [self getQueryOptions];
    if (!options)
        return kCBLStatusBadParam;

    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kCBLStatusBadJSON;
    NSArray* docIDs = body[@"keys"];
    if (![docIDs isKindOfClass: [NSArray class]])
        return kCBLStatusBadParam;
    options.keys = docIDs;
    return [self doAllDocs: options];
}

- (CBLStatus) doAllDocs: (CBLQueryOptions*)options {
    NSArray* result = [_db getAllDocs: options];
    if (!result)
        return _db.lastDbError;
    result = [result my_map: ^id(CBLQueryRow* row) {
        row.database = _db;
        return row.asJSONDictionary;
    }];
    _response.bodyObject = $dict({@"rows", result},
                                 {@"total_rows", @(result.count)},
                                 {@"offset", @(options->skip)},
                                 {@"update_seq", (options->updateSeq ? @(_db.lastSequenceNumber) : nil)});
    return kCBLStatusOK;
}


- (CBLStatus) do_POST_bulk_docs: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    NSDictionary* body = self.bodyAsDictionary;
    NSArray* docs = $castIf(NSArray, body[@"docs"]);
    if (!docs)
        return kCBLStatusBadParam;
    id allObj = body[@"all_or_nothing"];
    BOOL allOrNothing = (allObj && allObj != $false);
    BOOL noNewEdits = (body[@"new_edits"] == $false);

    return [_db _inTransaction: ^CBLStatus {
        NSMutableArray* results = [NSMutableArray arrayWithCapacity: docs.count];
        for (NSDictionary* doc in docs) {
            @autoreleasepool {
                NSString* docID = doc.cbl_id;
                CBL_Revision* rev;
                CBLStatus status;
                CBL_Body* docBody = [CBL_Body bodyWithProperties: doc];
                if (noNewEdits) {
                    rev = [[CBL_Revision alloc] initWithBody: docBody];
                    NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: doc];
                    status = rev ? [db forceInsert: rev revisionHistory: history source: nil]
                                 : kCBLStatusBadParam;
                } else {
                    status = [self update: db
                                    docID: docID
                                     body: docBody
                                 deleting: NO
                            allowConflict: allOrNothing
                               createdRev: &rev];
                }
                NSDictionary* result = nil;
                if (status < 300) {
                    Assert(rev.revID);
                    if (!noNewEdits)
                        result = $dict({@"id", rev.docID}, {@"rev", rev.revID}, {@"ok", $true});
                } else if (status >= 500) {
                    return status;  // abort the whole thing if something goes badly wrong
                } else if (allOrNothing) {
                    return status;  // all_or_nothing backs out if there's any error
                } else {
                    NSString* error = nil;
                    status = CBLStatusToHTTPStatus(status, &error);
                    result = $dict({@"id", docID}, {@"error", error}, {@"status", @(status)});
                }
                if (result)
                    [results addObject: result];
            }
        }
        _response.bodyObject = results;
        return kCBLStatusCreated;
    }];
}


- (CBLStatus) do_POST_revs_diff: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HttpPostRevsDiff
    // Collect all of the input doc/revision IDs as CBL_Revisions:
    CBL_RevisionList* revs = [[CBL_RevisionList alloc] init];
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kCBLStatusBadJSON;
    for (NSString* docID in body) {
        NSArray* revIDs = body[docID];
        if (![revIDs isKindOfClass: [NSArray class]])
            return kCBLStatusBadParam;
        for (NSString* revID in revIDs) {
            CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: revID deleted: NO];
            [revs addRev: rev];
        }
    }
    
    // Look them up, removing the existing ones from revs:
    if (![db findMissingRevisions: revs])
        return db.lastDbError;
    
    // Return the missing revs in a somewhat different format:
    NSMutableDictionary* diffs = $mdict();
    for (CBL_Revision* rev in revs) {
        NSString* docID = rev.docID;
        NSMutableArray* revs = diffs[docID][@"missing"];
        if (!revs) {
            revs = $marray();
            diffs[docID] = $mdict({@"missing", revs});
        }
        [revs addObject: rev.revID];
    }
    
    // Add the possible ancestors for each missing revision:
    for (NSString* docID in diffs) {
        NSMutableDictionary* docInfo = diffs[docID];
        int maxGen = 0;
        NSString* maxRevID = nil;
        for (NSString* revID in docInfo[@"missing"]) {
            int gen;
            if ([CBL_Revision parseRevID: revID intoGeneration: &gen andSuffix: NULL] && gen > maxGen) {
                maxGen = gen;
                maxRevID = revID;
            }
        }
        CBL_Revision* rev = [[CBL_Revision alloc] initWithDocID: docID revID: maxRevID deleted: NO];
        NSArray* ancestors = [_db getPossibleAncestorRevisionIDs: rev limit: 0 hasAttachment: NULL];
        if (ancestors)
            docInfo[@"possible_ancestors"] = ancestors;
    }
                                    
    _response.bodyObject = diffs;
    return kCBLStatusOK;
}


- (CBLStatus) do_POST_compact: (CBLDatabase*)db {
    CBLStatus status = [db compact];
    return status<300 ? kCBLStatusAccepted : status;   // CouchDB returns 202 'cause it's async
}

- (CBLStatus) do_POST_ensure_full_commit: (CBLDatabase*)db {
    return kCBLStatusOK;
}


#pragma mark - REPLICATION & ACTIVE TASKS


- (CBLStatus) do_POST_replicate {
    NSDictionary* body = self.bodyAsDictionary;
    CBLStatus status;
    CBL_Replicator* repl = [_dbManager replicatorWithProperties: body status: &status];
    if (!repl)
        return status;

    if ([$castIf(NSNumber, body[@"cancel"]) boolValue]) {
        // Cancel replication:
        if (!repl.running)
            return kCBLStatusNotFound;
        [repl stop];
        return kCBLStatusOK;
    } else {
        // Start replication:
        [repl start];
        if (repl.continuous || [$castIf(NSNumber, body[@"async"]) boolValue]) {
            _response.bodyObject = $dict({@"session_id", repl.sessionID});
            return kCBLStatusOK;
        } else {
            // Non-continuous replication: don't send any response till it completes
            [[NSNotificationCenter defaultCenter] addObserver: self
                                                     selector: @selector(replicationStopped:)
                                                         name: CBL_ReplicatorStoppedNotification
                                                       object: repl];
            return 0;
        }
    }
}

// subroutine of -do_POST_replicate
- (void) replicationStopped: (NSNotification*)n {
    CBL_Replicator* repl = n.object;
    _response.status = CBLStatusFromNSError(repl.error, kCBLStatusServerError);
    [self sendResponseHeaders];
    [self.response setBodyObject: $dict({@"ok", (repl.error ?nil :$true)},
                                        {@"session_id", repl.sessionID})];
    [self sendResponseBodyAndFinish: YES];
}


/* CouchDB 1.2's _replicate response looks like this:
 {
    "history": [
        {
            "doc_write_failures": 0, 
            "docs_read": 18, 
            "docs_written": 18, 
            "end_last_seq": 19, 
            "end_time": "Thu, 20 Jun 2013 16:58:13 GMT", 
            "missing_checked": 18, 
            "missing_found": 18, 
            "recorded_seq": 19, 
            "session_id": "1cef7405d0e61fb0decc89323669a012", 
            "start_last_seq": 0, 
            "start_time": "Thu, 20 Jun 2013 16:58:13 GMT"
        }
    ], 
    "ok": true, 
    "replication_id_version": 2, 
    "session_id": "1cef7405d0e61fb0decc89323669a012", 
    "source_last_seq": 19
}
*/


- (CBLStatus) do_GET_active_tasks {
    // http://wiki.apache.org/couchdb/HttpGetActiveTasks

    // Get the current task info of all replicators:
    NSMutableArray* activity = $marray();
    for (CBLDatabase* db in _dbManager.allOpenDatabases) {
        for (CBL_Replicator* repl in db.activeReplicators) {
            [activity addObject: repl.activeTaskInfo];
        }
    }

    if ([[self query: @"feed"] isEqualToString: @"continuous"]) {
        // Continuous activity feed (this is a CBL-specific API):
        [self sendResponseHeaders];
        for (NSDictionary* item in activity)
            [self sendContinuousLine: item];

        // Listen for activity changes:
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(replicationChanged:)
                                                     name: CBL_ReplicatorProgressChangedNotification
                                                   object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(replicationChanged:)
                                                     name: CBL_ReplicatorStoppedNotification
                                                   object: nil];
        // Don't close connection; more data to come
        return 0;
        
    } else {
        // Normal (CouchDB-style) snapshot of activity:
        _response.body = [[CBL_Body alloc] initWithArray: activity];
        return kCBLStatusOK;
    }
}

// subroutine of do_GET_active_tasks
- (void) replicationChanged: (NSNotification*)n {
    CBL_Replicator* repl = n.object;
    if (repl.db.manager == _dbManager)
        [self sendContinuousLine: repl.activeTaskInfo];
}


#pragma mark - CHANGES:


- (NSDictionary*) changeDictForRev: (CBL_Revision*)rev {
    return $dict({@"seq", @(rev.sequence)},
                 {@"id",  rev.docID},
                 {@"changes", $marray($dict({@"rev", rev.revID}))},
                 {@"deleted", rev.deleted ? $true : nil},
                 {@"doc", (_changesIncludeDocs ? rev.properties : nil)});
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


// Send a JSON object followed by a newline without closing the connection.
// Used by the continuous mode of _changes and _active_tasks.
- (void) sendContinuousLine: (NSDictionary*)changeDict {
    NSMutableData* json = [[CBLJSON dataWithJSONObject: changeDict
                                               options: 0 error: NULL] mutableCopy];
    [json appendBytes: "\n" length: 1];
    if (_onDataAvailable)
        _onDataAvailable(json, NO);
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

        if (_longpoll) {
            [changes addObject: rev];
        } else {
            Log(@"CBL_Router: Sending continous change chunk");
            [self sendContinuousLine: [self changeDictForRev: rev]];
        }
    }

    if (_longpoll && changes.count > 0) {
        Log(@"CBL_Router: Sending longpoll response");
        [self sendResponseHeaders];
        NSDictionary* body = [self responseBodyForChanges: changes since: 0];
        _response.body = [CBL_Body bodyWithProperties: body];
        [self sendResponseBodyAndFinish: YES];
    }

    retainSelf = nil;
}


- (CBLStatus) do_GET_changes: (CBLDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    
    NSString* feed = [self query: @"feed"];
    _longpoll = $equal(feed, @"longpoll");
    BOOL continuous = !_longpoll && $equal(feed, @"continuous");
    
    // Regular poll is cacheable:
    if (!_longpoll && !continuous && [self cacheWithEtag: $sprintf(@"%lld", _db.lastSequenceNumber)])
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
    
    
    if (continuous || (_longpoll && changes.count==0)) {
        // Response is going to stay open (continuous, or hanging GET):
        if (continuous) {
            [self sendResponseHeaders];
            for (CBL_Revision* rev in changes) 
                [self sendContinuousLine: [self changeDictForRev: rev]];
        }
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(dbChanged:)
                                                     name: CBL_DatabaseChangesNotification
                                                   object: db];
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


#pragma mark - DOCUMENT REQUESTS:


static NSArray* parseJSONRevArrayQuery(NSString* queryStr) {
    queryStr = [queryStr stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    if (!queryStr)
        return nil;
    NSData* queryData = [queryStr dataUsingEncoding: NSUTF8StringEncoding];
    return $castIfArrayOf(NSString, [CBLJSON JSONObjectWithData: queryData
                                                       options: 0
                                                         error: NULL]);
}

- (CBLStatus)do_OPTIONS: (CBLDatabase *)db docID:(NSString *)docID {
    return kCBLStatusOK;
}

- (CBLStatus) do_GET: (CBLDatabase*)db docID: (NSString*)docID {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#GET
    BOOL isLocalDoc = [docID hasPrefix: @"_local/"];
    CBLContentOptions options = [self contentOptions];
    NSString* openRevsParam = [self query: @"open_revs"];
    BOOL mustSendJSON = [self explicitlyAcceptsType: @"application/json"];
    if (openRevsParam == nil || isLocalDoc) {
        // Regular GET:
        NSString* revID = [self query: @"rev"];  // often nil
        CBL_Revision* rev;
        BOOL includeAttachments = NO, sendMultipart = NO;
        if (isLocalDoc) {
            rev = [db getLocalDocumentWithID: docID revisionID: revID];
        } else {
            includeAttachments = (options & kCBLIncludeAttachments) != 0;
            if (includeAttachments) {
                sendMultipart = !mustSendJSON;
                if (sendMultipart)
                    options &= ~kCBLIncludeAttachments;
            }
            CBLStatus status;
            rev = [db getDocumentWithID: docID revisionID: revID options: options status: &status];
            if (!rev) {
                if (status == kCBLStatusDeleted)
                    _response.statusReason = @"deleted";
                else
                    _response.statusReason = @"missing";
                return status;
            }
        }

        if (!rev)
            return kCBLStatusNotFound;
        if ([self cacheWithEtag: rev.revID])        // set ETag and check conditional GET
            return kCBLStatusNotModified;
        
        if (includeAttachments) {
            int minRevPos = 1;
            NSArray* attsSince = parseJSONRevArrayQuery([self query: @"atts_since"]);
            NSString* ancestorID = [_db findCommonAncestorOf: rev withRevIDs: attsSince];
            if (ancestorID)
                minRevPos = [CBL_Revision generationFromRevID: ancestorID] + 1;
            CBL_MutableRevision* stubbedRev = rev.mutableCopy;
            [CBLDatabase stubOutAttachmentsIn: stubbedRev beforeRevPos: minRevPos
                            attachmentsFollow: sendMultipart];
            rev = stubbedRev;
        }

        if (sendMultipart)
            [_response setMultipartBody: [db multipartWriterForRevision: rev
                                                            contentType: @"multipart/related"]];
        else
            _response.body = rev.body;
        
    } else {
        // open_revs query:
        NSMutableArray* result;
        if ($equal(openRevsParam, @"all")) {
            // ?open_revs=all returns all current/leaf revisions:
            BOOL includeDeleted = [self boolQuery: @"include_deleted"];
            CBL_RevisionList* allRevs = [_db getAllRevisionsOfDocumentID: docID onlyCurrent: YES];
            result = [NSMutableArray arrayWithCapacity: allRevs.count];
            for (CBL_Revision* rev in allRevs.allRevisions) {
                if (!includeDeleted && rev.deleted)
                    continue;
                CBLStatus status;
                CBL_Revision* loadedRev = [_db revisionByLoadingBody: rev options: options
                                                              status: &status];
                if (loadedRev)
                    [result addObject: $dict({@"ok", loadedRev.properties})];
                else if (status < kCBLStatusServerError)
                    [result addObject: $dict({@"missing", rev.revID})];
                else
                    return status;  // internal error getting revision
            }
                
        } else {
            // ?open_revs=[...] returns an array of specific revisions of the document:
            NSArray* openRevs = $castIf(NSArray, [self jsonQuery: @"open_revs" error: NULL]);
            if (!openRevs)
                return kCBLStatusBadParam;
            result = [NSMutableArray arrayWithCapacity: openRevs.count];
            for (NSString* revID in openRevs) {
                if (![revID isKindOfClass: [NSString class]])
                    return kCBLStatusBadID;
                CBLStatus status;
                CBL_Revision* rev = [db getDocumentWithID: docID revisionID: revID
                                                options: options status: &status];
                if (rev)
                    [result addObject: $dict({@"ok", rev.properties})];
                else
                    [result addObject: $dict({@"missing", revID})];
            }
        }

        // Response type defaults to multipart unless JSON is specified:
        if (mustSendJSON)
            _response.bodyObject = result;
        else
            [_response setMultipartBody: result type: @"multipart/mixed"];
    }
    return kCBLStatusOK;
}


- (CBLStatus) do_GET: (CBLDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    CBLStatus status;
    CBL_Revision* rev = [db getDocumentWithID: docID
                                 revisionID: [self query: @"rev"]  // often nil
                                    options: kCBLNoBody
                                     status: &status];        // all we need is revID & sequence
    if (!rev)
        return status;
    if ([self cacheWithEtag: rev.revID])        // set ETag and check conditional GET
        return kCBLStatusNotModified;
    
    NSString* type = nil;
    CBLAttachmentEncoding encoding = kCBLAttachmentEncodingNone;
    NSString* acceptEncoding = [_request valueForHTTPHeaderField: @"Accept-Encoding"];
    BOOL acceptEncoded = (acceptEncoding
                          && [acceptEncoding rangeOfString: @"gzip"].length > 0
                          && [_request valueForHTTPHeaderField: @"Range"] == nil);

    if ($equal(_request.HTTPMethod, @"HEAD")) {
        NSString* filePath = [_db getAttachmentPathForSequence: rev.sequence
                                                         named: attachment
                                                          type: &type
                                                      encoding: &encoding
                                                        status: &status];
        if (!filePath)
            return status;
        if (_local) {
            // Let in-app clients know the location of the attachment file:
            _response[@"Location"] = [[NSURL fileURLWithPath: filePath] absoluteString];
        }
        UInt64 size = [[[NSFileManager defaultManager] attributesOfItemAtPath: filePath
                                                                          error: nil]
                                    fileSize];
        if (size)
            _response[@"Content-Length"] = $sprintf(@"%llu", size);
        
    } else {
        NSData* contents = [_db getAttachmentForSequence: rev.sequence
                                                   named: attachment
                                                    type: &type
                                                encoding: (acceptEncoded ? &encoding : NULL)
                                                  status: &status];
        if (!contents)
            return status;
        _response.body = [CBL_Body bodyWithJSON: contents];   //FIX: This is a lie, it's not JSON
    }
    if (type)
        _response[@"Content-Type"] = type;
    if (encoding == kCBLAttachmentEncodingGZIP)
        _response[@"Content-Encoding"] = @"gzip";
    return kCBLStatusOK;
}


- (CBLStatus) update: (CBLDatabase*)db
              docID: (NSString*)docID
               body: (CBL_Body*)body
           deleting: (BOOL)deleting
      allowConflict: (BOOL)allowConflict
         createdRev: (CBL_Revision**)outRev
{
    if (body && !body.isValidJSON)
        return kCBLStatusBadJSON;
    
    NSString* prevRevID;
    
    if (!deleting) {
        NSDictionary* properties = body.properties;
        deleting = properties.cbl_deleted;
        if (!docID) {
            // POST's doc ID may come from the _id field of the JSON body.
            docID = properties.cbl_id;
            if (!docID && deleting)
                return kCBLStatusBadID;
        }
        // PUT's revision ID comes from the JSON body.
        prevRevID = properties.cbl_rev;
    } else {
        // DELETE's revision ID comes from the ?rev= query param
        prevRevID = [self query: @"rev"];
    }

    // A backup source of revision ID is an If-Match header:
    if (!prevRevID)
        prevRevID = self.ifMatch;

    CBL_MutableRevision* rev = [[CBL_MutableRevision alloc] initWithDocID: docID revID: nil
                                                                  deleted: deleting];
    if (!rev)
        return kCBLStatusBadID;
    rev.body = body;
    
    CBLStatus status;
    if ([docID hasPrefix: @"_local/"])
        *outRev = [db putLocalRevision: rev prevRevisionID: prevRevID status: &status];
    else
        *outRev = [db putRevision: rev prevRevisionID: prevRevID
                    allowConflict: allowConflict
                           status: &status];
    return status;
}


- (CBLStatus) update: (CBLDatabase*)db
              docID: (NSString*)docID
               body: (CBL_Body*)body
           deleting: (BOOL)deleting
{
    if (docID) {
        // On PUT/DELETE, get revision ID from either ?rev= query, If-Match: header, or doc body:
        NSString* revParam = [self query: @"rev"];
        NSString* ifMatch = [_request valueForHTTPHeaderField: @"If-Match"];
        if (ifMatch) {
            if (!revParam)
                revParam = ifMatch;
            else if (!$equal(revParam, ifMatch))
                return 400;
        }
        if (revParam && body) {
            id revProp = body.properties.cbl_rev;
            if (!revProp) {
                // No _rev property in body, so use ?rev= query param instead:
                NSMutableDictionary* props = body.properties.mutableCopy;
                props[@"_rev"] = revParam;
                body = [CBL_Body bodyWithProperties: props];
            } else if (!$equal(revProp, revParam)) {
                return 400; // mismatch between _rev and rev
            }
        }
    }

    CBL_Revision* rev;
    CBLStatus status = [self update: db docID: docID body: body
                           deleting: deleting
                      allowConflict: NO
                         createdRev: &rev];
    if (status < 300) {
        [self cacheWithEtag: rev.revID];        // set ETag
        if (!deleting) {
            NSURL* url = _request.URL;
            if (!docID)
                url = [url URLByAppendingPathComponent: rev.docID];
            [self setResponseLocation: url];
        }
        _response.bodyObject = $dict({@"ok", $true},
                                     {@"id", rev.docID},
                                     {@"rev", rev.revID});
    }
    return status;
}


- (CBLStatus) readDocumentBodyThen: (CBLStatus(^)(CBL_Body*))block {
    CBLStatus status;
    NSDictionary* headers = _request.allHTTPHeaderFields;
    NSInputStream* bodyStream = _request.HTTPBodyStream;
    if (bodyStream) {
        block = [block copy];
        status = [CBLMultipartDocumentReader readStream: bodyStream
                                                headers: headers
                                             toDatabase: _db
                                                   then: ^(CBLMultipartDocumentReader* reader) {
            // Called when the reader is done reading/parsing the stream:
            CBLStatus status = reader.status;
            if (!CBLStatusIsError(status)) {
                NSDictionary* properties = reader.document;
                if (properties)
                    status = block([CBL_Body bodyWithProperties: properties]);
                else
                    status = kCBLStatusBadRequest;
            }
            _response.internalStatus = status;
            [self finished];
        }];

        if (CBLStatusIsError(status))
            return status;
        // Don't close connection; more data to come
        return 0;

    } else {
        NSDictionary* properties = [CBLMultipartDocumentReader readData: _request.HTTPBody
                                                                headers: headers
                                                             toDatabase: _db
                                                                 status: &status];
        if (CBLStatusIsError(status))
            return status;
        else if (!properties)
            return kCBLStatusBadRequest;
        return block([CBL_Body bodyWithProperties: properties]);
    }
}


- (CBLStatus) do_POST: (CBLDatabase*)db {
    CBLStatus status = [self openDB];
    if (CBLStatusIsError(status))
        return status;
    return [self readDocumentBodyThen: ^(CBL_Body *body) {
        return [self update: db docID: nil body: body deleting: NO];
    }];
}


- (CBLStatus) do_PUT: (CBLDatabase*)db docID: (NSString*)docID {
    return [self readDocumentBodyThen: ^CBLStatus(CBL_Body *body) {
        if (![self query: @"new_edits"] || [self boolQuery: @"new_edits"]) {
            // Regular PUT:
            return [self update: db docID: docID body: body deleting: NO];
        } else {
            // PUT with new_edits=false -- forcible insertion of existing revision:
            CBL_Revision* rev = [[CBL_Revision alloc] initWithBody: body];
            if (!rev)
                return kCBLStatusBadJSON;
            if (!$equal(rev.docID, docID) || !rev.revID)
                return kCBLStatusBadID;
            NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: body.properties];
            CBLStatus status = [_db forceInsert: rev revisionHistory: history source: nil];
            if (!CBLStatusIsError(status)) {
                _response.bodyObject = $dict({@"ok", $true},
                                             {@"id", rev.docID},
                                             {@"rev", rev.revID});
            }
            return status;
        }
    }];
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db docID: (NSString*)docID {
    return [self update: db docID: docID body: nil deleting: YES];
}


- (CBLStatus) updateAttachment: (NSString*)attachment
                        docID: (NSString*)docID
                         body: (CBL_BlobStoreWriter*)body
{
    CBLStatus status;
    CBL_Revision* rev = [_db updateAttachment: attachment 
                                       body: body
                                       type: [_request valueForHTTPHeaderField: @"Content-Type"]
                                   encoding: kCBLAttachmentEncodingNone
                                    ofDocID: docID
                                      revID: ([self query: @"rev"] ?: self.ifMatch)
                                     status: &status];
    if (status < 300) {
        _response.bodyObject = $dict({@"ok", $true}, {@"id", rev.docID}, {@"rev", rev.revID});
        [self cacheWithEtag: rev.revID];
        if (body)
            [self setResponseLocation: _request.URL];
    }
    return status;
}


- (CBLStatus) do_PUT: (CBLDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    CBL_BlobStoreWriter* blob = db.attachmentWriter;
    NSInputStream* bodyStream = _request.HTTPBodyStream;
    if (bodyStream) {
        // OPT: Should read this asynchronously
        NSMutableData* buffer = [NSMutableData dataWithLength: 32768];
        NSInteger bytesRead;
        do {
            bytesRead = [bodyStream read: buffer.mutableBytes maxLength: buffer.length];
            if (bytesRead > 0) {
                [blob appendData: [NSData dataWithBytesNoCopy: buffer.mutableBytes
                                                       length: bytesRead freeWhenDone: NO]];
            }
        } while (bytesRead > 0);
        if (bytesRead < 0)
            return kCBLStatusBadAttachment;
        
    } else {
        NSData* body = _request.HTTPBody;
        if (body)
            [blob appendData: body];
    }
    [blob finish];

    return [self updateAttachment: attachment docID: docID body: blob];
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    return [self updateAttachment: attachment docID: docID body: nil];
}


#pragma mark - VIEW QUERIES:


- (CBLStatus) queryDesignDoc: (NSString*)designDoc view: (NSString*)viewName keys: (NSArray*)keys {
    NSString* tdViewName = $sprintf(@"%@/%@", designDoc, viewName);
    CBLStatus status;
    CBLView* view = [_db compileViewNamed: tdViewName status: &status];
    if (!view)
        return status;
    
    CBLQueryOptions *options = [self getQueryOptions];
    if (!options)
        return kCBLStatusBadRequest;
    if (keys)
        options.keys = keys;

    status = [view updateIndex];
    if (status >= kCBLStatusBadRequest)
        return status;
    
    // Check for conditional GET and set response Etag header:
    if (!keys) {
        SequenceNumber eTag = options->includeDocs ? _db.lastSequenceNumber : view.lastSequenceIndexed;
        if ([self cacheWithEtag: $sprintf(@"%lld", eTag)])
            return kCBLStatusNotModified;
    }
    return [self queryView: view withOptions: options];
}


- (CBLStatus) queryView: (CBLView*)view withOptions: (CBLQueryOptions*)options {
    CBLStatus status;
    NSArray* rows = [view _queryWithOptions: options status: &status];
    if (!rows)
        return status;
    rows = [rows my_map:^(CBLQueryRow* row) {
        row.database = _db;
        return row.asJSONDictionary;
    }];
    id updateSeq = options->updateSeq ? @(view.lastSequenceIndexed) : nil;
    _response.bodyObject = $dict({@"rows", rows},
                                 {@"total_rows", @(view.totalRows)},
                                 {@"offset", @(options->skip)},
                                 {@"update_seq", updateSeq});
    return kCBLStatusOK;
}


- (CBLStatus) do_GET: (CBLDatabase*)db designDocID: (NSString*)designDoc view: (NSString*)viewName {
    return [self queryDesignDoc: designDoc view: viewName keys: nil];
}


- (CBLStatus) do_POST: (CBLDatabase*)db designDocID: (NSString*)designDoc view: (NSString*)viewName {
    NSArray* keys = $castIf(NSArray, (self.bodyAsDictionary)[@"keys"]);
    if (!keys)
        return kCBLStatusBadParam;
    return [self queryDesignDoc: designDoc view: viewName keys: keys];
}


- (CBLStatus) do_POST_temp_view: (CBLDatabase*)db {
    if (![[_request valueForHTTPHeaderField: @"Content-Type"] hasPrefix: @"application/json"])
        return kCBLStatusUnsupportedType;
    CBL_Body* requestBody = [CBL_Body bodyWithJSON: _request.HTTPBody];
    if (!requestBody.isValidJSON)
        return kCBLStatusBadJSON;
    NSDictionary* props = requestBody.properties;
    if (!props)
        return kCBLStatusBadJSON;
    
    CBLQueryOptions *options = [self getQueryOptions];
    if (!options)
        return kCBLStatusBadRequest;
    
    if ([self cacheWithEtag: $sprintf(@"%lld", _db.lastSequenceNumber)])  // conditional GET
        return kCBLStatusNotModified;

    CBLView* view = [_db viewNamed: @"@@TEMPVIEW@@"];
    if (![view compileFromProperties: props language: @"javascript"])
        return kCBLStatusBadRequest;

    @try {
        CBLStatus status = [view updateIndex];
        if (status >= kCBLStatusBadRequest)
            return status;
        return [self queryView: view withOptions: options];
    } @finally {
        [view deleteView];
    }
}


@end
