//
//  TDRouter+Handlers.m
//  TouchDB
//
//  Created by Jens Alfke on 1/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDRouter.h"
#import <TouchDB/TDDatabase.h>
#import "TDDatabase+Attachments.h"
#import "TDDatabase+Insertion.h"
#import "TDDatabase+LocalDocs.h"
#import "TDDatabase+Replication.h"
#import "TDView.h"
#import "TDBody.h"
#import "TDMultipartDocumentReader.h"
#import <TouchDB/TDRevision.h>
#import "TDServer.h"
#import "TDReplicator.h"
#import "TDReplicatorManager.h"
#import "TDPusher.h"
#import "TDInternal.h"
#import "TDMisc.h"


@implementation TDRouter (Handlers)


- (void) setResponseLocation: (NSURL*)url {
    // Strip anything after the URL's path (i.e. the query string)
    _response[@"Location"] = TDURLWithoutQuery(url).absoluteString;
}


#pragma mark - SERVER REQUESTS:


- (TDStatus) do_GETRoot {
    NSDictionary* info = $dict({@"TouchDB", @"Welcome"},
                               {@"couchdb", @"Welcome"},        // for compatibility
                               {@"version", [[self class] versionString]});
    _response.body = [TDBody bodyWithProperties: info];
    return kTDStatusOK;
}

- (TDStatus) do_GET_all_dbs {
    NSArray* dbs = _dbManager.allDatabaseNames ?: @[];
    _response.body = [[[TDBody alloc] initWithArray: dbs] autorelease];
    return kTDStatusOK;
}

- (TDStatus) do_POST_replicate {
    // Extract the parameters from the JSON request body:
    // http://wiki.apache.org/couchdb/Replication
    TDDatabase* db;
    NSURL* remote;
    BOOL push, createTarget;
    NSDictionary* headers;
    id<TDAuthorizer> authorizer;
    NSDictionary* body = self.bodyAsDictionary;
    TDStatus status = [_dbManager.replicatorManager parseReplicatorProperties: body
                                                                   toDatabase: &db remote: &remote
                                                                       isPush: &push
                                                                 createTarget: &createTarget
                                                                      headers: &headers
                                                                   authorizer: &authorizer];
    if (TDStatusIsError(status))
        return status;
    
    BOOL continuous = [$castIf(NSNumber, body[@"continuous"]) boolValue];
    BOOL cancel = [$castIf(NSNumber, body[@"cancel"]) boolValue];
    if (!cancel) {
        // Start replication:
        TDReplicator* repl = [db replicatorWithRemoteURL: remote push: push continuous: continuous];
        if (!repl)
            return kTDStatusServerError;
        repl.filterName = $castIf(NSString, body[@"filter"]);;
        repl.filterParameters = $castIf(NSDictionary, body[@"query_params"]);
        repl.options = body;
        repl.requestHeaders = headers;
        repl.authorizer = authorizer;
        if (push)
            ((TDPusher*)repl).createTarget = createTarget;
        [repl start];
        _response.bodyObject = $dict({@"session_id", repl.sessionID});
    } else {
        // Cancel replication:
        TDReplicator* repl = [db activeReplicatorWithRemoteURL: remote push: push];
        if (!repl)
            return kTDStatusNotFound;
        [repl stop];
    }
    return kTDStatusOK;
}


- (TDStatus) do_GET_uuids {
    int count = MIN(1000, [self intQuery: @"count" defaultValue: 1]);
    NSMutableArray* uuids = [NSMutableArray arrayWithCapacity: count];
    for (int i=0; i<count; i++)
        [uuids addObject: [TDDatabase generateDocumentID]];
    _response.bodyObject = $dict({@"uuids", uuids});
    return kTDStatusOK;
}


- (TDStatus) do_GET_active_tasks {
    // http://wiki.apache.org/couchdb/HttpGetActiveTasks
    NSMutableArray* activity = $marray();
    for (TDDatabase* db in _dbManager.allOpenDatabases) {
        for (TDReplicator* repl in db.activeReplicators) {
            NSString* source = repl.remote.absoluteString;
            NSString* target = db.name;
            if (repl.isPush) {
                NSString* temp = source;
                source = target;
                target = temp;
            }
            NSString* status;
            id progress = nil;
            if (!repl.running) {
                status = @"Stopped";
            } else if (!repl.online) {
                status = @"Offline";        // nonstandard
            } else if (!repl.active) {
                status = @"Idle";           // nonstandard
            } else {
                NSUInteger processed = repl.changesProcessed;
                NSUInteger total = repl.changesTotal;
                status = $sprintf(@"Processed %u / %u changes",
                                  (unsigned)processed, (unsigned)total);
                progress = (total>0) ? @(lroundf(100*(processed / (float)total))) : nil;
            }
            NSArray* error = nil;
            NSError* errorObj = repl.error;
            if (errorObj)
                error = @[@(errorObj.code), errorObj.localizedDescription];

            [activity addObject: $dict({@"type", @"Replication"},
                                       {@"task", repl.sessionID},
                                       {@"source", source},
                                       {@"target", target},
                                       {@"continuous", (repl.continuous ? $true : nil)},
                                       {@"status", status},
                                       {@"progress", progress},
                                       {@"x_active_requests", repl.activeRequestsStatus},
                                       {@"error", error})];
        }
    }
    _response.body = [[[TDBody alloc] initWithArray: activity] autorelease];
    return kTDStatusOK;
}


- (TDStatus) do_GET_session {
    // Even though TouchDB doesn't support user logins, it implements a generic response to the
    // CouchDB _session API, so that apps that call it (such as Futon!) won't barf.
    _response.bodyObject = $dict({@"ok", $true},
                                 {@"userCtx", $dict({@"name", $null},
                                                    {@"roles", @[@"_admin"]})});
    return kTDStatusOK;
}


#pragma mark - DATABASE REQUESTS:


- (TDStatus) do_GET: (TDDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Database_Information
    TDStatus status = [self openDB];
    if (TDStatusIsError(status))
        return status;
    NSUInteger num_docs = db.documentCount;
    SequenceNumber update_seq = db.lastSequence;
    if (num_docs == NSNotFound || update_seq == NSNotFound)
        return kTDStatusDBError;
    _response.bodyObject = $dict({@"db_name", db.name},
                                 {@"db_uuid", db.publicUUID},
                                 {@"doc_count", @(num_docs)},
                                 {@"update_seq", @(update_seq)},
                                 {@"disk_size", @(db.totalDataSize)});
    return kTDStatusOK;
}


- (TDStatus) do_PUT: (TDDatabase*)db {
    if (db.exists)
        return kTDStatusDuplicate;
    if (![db open])
        return kTDStatusDBError;
    [self setResponseLocation: _request.URL];
    return kTDStatusCreated;
}


- (TDStatus) do_DELETE: (TDDatabase*)db {
    if ([self query: @"rev"])
        return kTDStatusBadID;  // CouchDB checks for this; probably meant to be a document deletion
    return [_dbManager deleteDatabaseNamed: db.name] ? kTDStatusOK : kTDStatusNotFound;
}


- (TDStatus) do_POST_purge: (TDDatabase*)db {
    // <http://wiki.apache.org/couchdb/Purge_Documents>
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kTDStatusBadJSON;
    NSDictionary* purgedDocs;
    TDStatus status = [db purgeRevisions: body result: &purgedDocs];
    if (TDStatusIsError(status))
        return status;
    _response.bodyObject = $dict({@"purged", purgedDocs});
    return status;
}


- (TDStatus) do_GET_all_docs: (TDDatabase*)db {
    if ([self cacheWithEtag: $sprintf(@"%lld", db.lastSequence)])
        return kTDStatusNotModified;
    
    TDQueryOptions options;
    if (![self getQueryOptions: &options])
        return kTDStatusBadParam;
    NSDictionary* result = [db getAllDocs: &options];
    if (!result)
        return kTDStatusDBError;
    _response.bodyObject = result;
    return kTDStatusOK;
}


- (TDStatus) do_POST_all_docs: (TDDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    TDQueryOptions options;
    if (![self getQueryOptions: &options])
        return kTDStatusBadParam;
    
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kTDStatusBadJSON;
    NSArray* docIDs = body[@"keys"];
    if (![docIDs isKindOfClass: [NSArray class]])
        return kTDStatusBadParam;
    
    NSDictionary* result = [db getDocsWithIDs: docIDs options: &options];
    if (!result)
        return kTDStatusDBError;
    _response.bodyObject = result;
    return kTDStatusOK;
}


- (TDStatus) do_POST_bulk_docs: (TDDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API
    NSDictionary* body = self.bodyAsDictionary;
    NSArray* docs = $castIf(NSArray, body[@"docs"]);
    if (!docs)
        return kTDStatusBadParam;
    id allObj = body[@"all_or_nothing"];
    BOOL allOrNothing = (allObj && allObj != $false);
    BOOL noNewEdits = (body[@"new_edits"] == $false);

    BOOL ok = NO;
    NSMutableArray* results = [NSMutableArray arrayWithCapacity: docs.count];
    [_db beginTransaction];
    @try{
        for (NSDictionary* doc in docs) {
            @autoreleasepool {
                NSString* docID = doc[@"_id"];
                TDRevision* rev;
                TDStatus status;
                TDBody* docBody = [TDBody bodyWithProperties: doc];
                if (noNewEdits) {
                    rev = [[[TDRevision alloc] initWithBody: docBody] autorelease];
                    NSArray* history = [TDDatabase parseCouchDBRevisionHistory: doc];
                    status = rev ? [db forceInsert: rev revisionHistory: history source: nil] : kTDStatusBadParam;
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
                } else if (allOrNothing) {
                    return status;  // all_or_nothing backs out if there's any error
                } else if (status == kTDStatusForbidden) {
                    result = $dict({@"id", docID}, {@"error", @"validation failed"});
                } else if (status == kTDStatusConflict) {
                    result = $dict({@"id", docID}, {@"error", @"conflict"});
                } else {
                    return status;  // abort the whole thing if something goes badly wrong
                }
                if (result)
                    [results addObject: result];
            }
        }
        ok = YES;
    } @finally {
        [_db endTransaction: ok];
    }
    
    _response.bodyObject = results;
    return kTDStatusCreated;
}


- (TDStatus) do_POST_revs_diff: (TDDatabase*)db {
    // http://wiki.apache.org/couchdb/HttpPostRevsDiff
    // Collect all of the input doc/revision IDs as TDRevisions:
    TDRevisionList* revs = [[[TDRevisionList alloc] init] autorelease];
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kTDStatusBadJSON;
    for (NSString* docID in body) {
        NSArray* revIDs = body[docID];
        if (![revIDs isKindOfClass: [NSArray class]])
            return kTDStatusBadParam;
        for (NSString* revID in revIDs) {
            TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: revID deleted: NO];
            [revs addRev: rev];
            [rev release];
        }
    }
    
    // Look them up, removing the existing ones from revs:
    if (![db findMissingRevisions: revs])
        return kTDStatusDBError;
    
    // Return the missing revs in a somewhat different format:
    NSMutableDictionary* diffs = $mdict();
    for (TDRevision* rev in revs) {
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
            if ([TDRevision parseRevID: revID intoGeneration: &gen andSuffix: NULL] && gen > maxGen) {
                maxGen = gen;
                maxRevID = revID;
            }
        }
        TDRevision* rev = [[TDRevision alloc] initWithDocID: docID revID: maxRevID deleted: NO];
        NSArray* ancestors = [_db getPossibleAncestorRevisionIDs: rev limit: 0];
        [rev release];
        if (ancestors)
            docInfo[@"possible_ancestors"] = ancestors;
    }
                                    
    _response.bodyObject = diffs;
    return kTDStatusOK;
}


- (TDStatus) do_POST_compact: (TDDatabase*)db {
    TDStatus status = [db compact];
    return status<300 ? kTDStatusAccepted : status;   // CouchDB returns 202 'cause it's async
}

- (TDStatus) do_POST_ensure_full_commit: (TDDatabase*)db {
    return kTDStatusOK;
}


#pragma mark - CHANGES:


- (NSDictionary*) changeDictForRev: (TDRevision*)rev {
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
    for (TDRevision* rev in changes) {
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
        return TDSequenceCompare([e1[@"seq"] longLongValue],
                                 [e2[@"seq"] longLongValue]);
    }];
    if (entries.count > limit)
        [entries removeObjectsInRange: NSMakeRange(limit, entries.count - limit)];
    id lastSeq = (entries.lastObject)[@"seq"] ?: @(since);
    return $dict({@"results", entries}, {@"last_seq", lastSeq});
}


- (void) sendContinuousChange: (TDRevision*)rev {
    NSDictionary* changeDict = [self changeDictForRev: rev];
    NSMutableData* json = [[TDJSON dataWithJSONObject: changeDict
                                              options: 0 error: NULL] mutableCopy];
    [json appendBytes: "\n" length: 1];
    if (_onDataAvailable)
        _onDataAvailable(json, NO);
    [json release];
}


- (void) dbChanged: (NSNotification*)n {
    NSDictionary* userInfo = n.userInfo;
    TDRevision* rev = userInfo[@"rev"];
    TDRevision* winningRev = userInfo[@"winner"];

    if (!_changesIncludeConflicts) {
        if (!winningRev)
            return;     // this change doesn't affect the winning rev ID, so no need to send it
        else if (!$equal(winningRev, rev)) {
            // This rev made a _different_ rev current, so substitute that one.
            // We need to emit the current sequence # in the feed, so put it in the rev.
            // This isn't correct internally (this is an old rev so it has an older sequence)
            // but consumers of the _changes feed don't care about the internal state.
            if (_changesIncludeDocs)
                [_db loadRevisionBody: winningRev options: 0];
            winningRev.sequence = rev.sequence;
            rev = winningRev;
        }
    }
    
    if (_changesFilter && !_changesFilter(rev, _changesFilterParams))
        return;

    if (_longpoll) {
        Log(@"TDRouter: Sending longpoll response");
        [self sendResponseHeaders];
        NSDictionary* body = [self responseBodyForChanges: @[rev] since: 0];
        _response.body = [TDBody bodyWithProperties: body];
        [self sendResponseBodyAndFinish: YES];
    } else {
        Log(@"TDRouter: Sending continous change chunk");
        [self sendContinuousChange: rev];
    }
}


- (TDStatus) do_GET_changes: (TDDatabase*)db {
    // http://wiki.apache.org/couchdb/HTTP_database_API#Changes
    
    NSString* feed = [self query: @"feed"];
    _longpoll = $equal(feed, @"longpoll");
    BOOL continuous = !_longpoll && $equal(feed, @"continuous");
    
    // Regular poll is cacheable:
    if (!_longpoll && !continuous && [self cacheWithEtag: $sprintf(@"%lld", _db.lastSequence)])
        return kTDStatusNotModified;

    // Get options:
    TDChangesOptions options = kDefaultTDChangesOptions;
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
        _changesFilter = [[_db filterNamed: filterName] retain];
        if (!_changesFilter)
            return kTDStatusNotFound;
        _changesFilterParams = [self.jsonQueries copy];
    }
    
    TDRevisionList* changes = [db changesSinceSequence: since
                                               options: &options
                                                filter: _changesFilter
                                                params: _changesFilterParams];
    if (!changes)
        return kTDStatusDBError;
    
    
    if (continuous || (_longpoll && changes.count==0)) {
        // Response is going to stay open (continuous, or hanging GET):
        if (continuous) {
            [self sendResponseHeaders];
            for (TDRevision* rev in changes) 
                [self sendContinuousChange: rev];
        }
        [[NSNotificationCenter defaultCenter] addObserver: self 
                                                 selector: @selector(dbChanged:)
                                                     name: TDDatabaseChangeNotification
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
        return kTDStatusOK;
    }
}


#pragma mark - DOCUMENT REQUESTS:


static NSArray* parseJSONRevArrayQuery(NSString* queryStr) {
    queryStr = [queryStr stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    if (!queryStr)
        return nil;
    NSData* queryData = [queryStr dataUsingEncoding: NSUTF8StringEncoding];
    return $castIfArrayOf(NSString, [TDJSON JSONObjectWithData: queryData
                                                       options: 0
                                                         error: NULL]);
}


- (TDStatus) do_GET: (TDDatabase*)db docID: (NSString*)docID {
    // http://wiki.apache.org/couchdb/HTTP_Document_API#GET
    BOOL isLocalDoc = [docID hasPrefix: @"_local/"];
    TDContentOptions options = [self contentOptions];
    NSString* acceptMultipart = self.multipartRequestType;
    NSString* openRevsParam = [self query: @"open_revs"];
    if (openRevsParam == nil || isLocalDoc) {
        // Regular GET:
        NSString* revID = [self query: @"rev"];  // often nil
        TDRevision* rev;
        BOOL includeAttachments = NO;
        if (isLocalDoc) {
            rev = [db getLocalDocumentWithID: docID revisionID: revID];
        } else {
            includeAttachments = (options & kTDIncludeAttachments) != 0;
            if (acceptMultipart)
                options &= ~kTDIncludeAttachments;
            TDStatus status;
            rev = [db getDocumentWithID: docID revisionID: revID options: options status: &status];
            if (!rev) {
                if (status == kTDStatusDeleted)
                    _response.statusReason = @"deleted";
                else
                    _response.statusReason = @"missing";
                return status;
            }
        }

        if (!rev)
            return kTDStatusNotFound;
        if ([self cacheWithEtag: rev.revID])        // set ETag and check conditional GET
            return kTDStatusNotModified;
        
        if (includeAttachments) {
            int minRevPos = 1;
            NSArray* attsSince = parseJSONRevArrayQuery([self query: @"atts_since"]);
            NSString* ancestorID = [_db findCommonAncestorOf: rev withRevIDs: attsSince];
            if (ancestorID)
                minRevPos = [TDRevision generationFromRevID: ancestorID] + 1;
            [TDDatabase stubOutAttachmentsIn: rev beforeRevPos: minRevPos
                           attachmentsFollow: (acceptMultipart != nil)];
        }

        if (acceptMultipart)
            [_response setMultipartBody: [db multipartWriterForRevision: rev
                                                            contentType: acceptMultipart]];
        else
            _response.body = rev.body;
        
    } else {
        // open_revs query:
        NSMutableArray* result;
        if ($equal(openRevsParam, @"all")) {
            // Get all conflicting revisions:
            BOOL includeDeleted = [self boolQuery: @"include_deleted"];
            TDRevisionList* allRevs = [_db getAllRevisionsOfDocumentID: docID onlyCurrent: YES];
            result = [NSMutableArray arrayWithCapacity: allRevs.count];
            for (TDRevision* rev in allRevs.allRevisions) {
                if (!includeDeleted && rev.deleted)
                    continue;
                TDStatus status = [_db loadRevisionBody: rev options: options];
                if (status < 300)
                    [result addObject: $dict({@"ok", rev.properties})];
                else if (status < kTDStatusServerError)
                    [result addObject: $dict({@"missing", rev.revID})];
                else
                    return status;  // internal error getting revision
            }
                
        } else {
            // ?open_revs=[...] returns an array of revisions of the document:
            NSArray* openRevs = $castIf(NSArray, [self jsonQuery: @"open_revs" error: NULL]);
            if (!openRevs)
                return kTDStatusBadParam;
            result = [NSMutableArray arrayWithCapacity: openRevs.count];
            for (NSString* revID in openRevs) {
                if (![revID isKindOfClass: [NSString class]])
                    return kTDStatusBadID;
                TDStatus status;
                TDRevision* rev = [db getDocumentWithID: docID revisionID: revID
                                                options: options status: &status];
                if (rev)
                    [result addObject: $dict({@"ok", rev.properties})];
                else
                    [result addObject: $dict({@"missing", revID})];
            }
        }
        if (acceptMultipart)
            [_response setMultipartBody: result type: acceptMultipart];
        else
            _response.bodyObject = result;
    }
    return kTDStatusOK;
}


- (TDStatus) do_GET: (TDDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    TDStatus status;
    TDRevision* rev = [db getDocumentWithID: docID
                                 revisionID: [self query: @"rev"]  // often nil
                                    options: kTDNoBody
                                     status: &status];        // all we need is revID & sequence
    if (!rev)
        return status;
    if ([self cacheWithEtag: rev.revID])        // set ETag and check conditional GET
        return kTDStatusNotModified;
    
    NSString* type = nil;
    TDAttachmentEncoding encoding = kTDAttachmentEncodingNone;
    NSString* acceptEncoding = [_request valueForHTTPHeaderField: @"Accept-Encoding"];
    BOOL acceptEncoded = (acceptEncoding && [acceptEncoding rangeOfString: @"gzip"].length > 0);

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
        _response.body = [TDBody bodyWithJSON: contents];   //FIX: This is a lie, it's not JSON
    }
    if (type)
        _response[@"Content-Type"] = type;
    if (encoding == kTDAttachmentEncodingGZIP)
        _response[@"Content-Encoding"] = @"gzip";
    return kTDStatusOK;
}


- (TDStatus) update: (TDDatabase*)db
              docID: (NSString*)docID
               body: (TDBody*)body
           deleting: (BOOL)deleting
      allowConflict: (BOOL)allowConflict
         createdRev: (TDRevision**)outRev
{
    if (body && !body.isValidJSON)
        return kTDStatusBadJSON;
    
    NSString* prevRevID;
    
    if (!deleting) {
        deleting = $castIf(NSNumber, body[@"_deleted"]).boolValue;
        if (!docID) {
            // POST's doc ID may come from the _id field of the JSON body.
            docID = body[@"_id"];
            if (!docID && deleting)
                return kTDStatusBadID;
        }
        // PUT's revision ID comes from the JSON body.
        prevRevID = body[@"_rev"];
    } else {
        // DELETE's revision ID comes from the ?rev= query param
        prevRevID = [self query: @"rev"];
    }

    // A backup source of revision ID is an If-Match header:
    if (!prevRevID)
        prevRevID = self.ifMatch;

    TDRevision* rev = [[[TDRevision alloc] initWithDocID: docID revID: nil deleted: deleting]
                            autorelease];
    if (!rev)
        return kTDStatusBadID;
    rev.body = body;
    
    TDStatus status;
    if ([docID hasPrefix: @"_local/"])
        *outRev = [db putLocalRevision: rev prevRevisionID: prevRevID status: &status];
    else
        *outRev = [db putRevision: rev prevRevisionID: prevRevID
                    allowConflict: allowConflict
                           status: &status];
    return status;
}


- (TDStatus) update: (TDDatabase*)db
              docID: (NSString*)docID
               body: (TDBody*)body
           deleting: (BOOL)deleting
{
    TDRevision* rev;
    TDStatus status = [self update: db docID: docID body: body
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


- (TDStatus) readDocumentBodyThen: (TDStatus(^)(TDBody*))block {
    TDStatus status;
    NSString* contentType = [_request valueForHTTPHeaderField: @"Content-Type"];
    NSInputStream* bodyStream = _request.HTTPBodyStream;
    if (bodyStream) {
        block = [[block copy] autorelease];
        status = [TDMultipartDocumentReader readStream: bodyStream
                                                ofType: contentType
                                            toDatabase: _db
                                                  then: ^(TDMultipartDocumentReader* reader) {
            // Called when the reader is done reading/parsing the stream:
            TDStatus status = reader.status;
            if (!TDStatusIsError(status)) {
                NSDictionary* properties = reader.document;
                if (properties)
                    status = block([TDBody bodyWithProperties: properties]);
                else
                    status = kTDStatusBadRequest;
            }
            _response.internalStatus = status;
            [self finished];
        }];

        if (TDStatusIsError(status))
            return status;
        // Don't close connection; more data to come
        return 0;

    } else {
        NSDictionary* properties = [TDMultipartDocumentReader readData: _request.HTTPBody
                                                                ofType: contentType
                                                            toDatabase: _db
                                                                status: &status];
        if (TDStatusIsError(status))
            return status;
        else if (!properties)
            return kTDStatusBadRequest;
        return block([TDBody bodyWithProperties: properties]);
    }
}


- (TDStatus) do_POST: (TDDatabase*)db {
    TDStatus status = [self openDB];
    if (TDStatusIsError(status))
        return status;
    return [self readDocumentBodyThen: ^(TDBody *body) {
        return [self update: db docID: nil body: body deleting: NO];
    }];
}


- (TDStatus) do_PUT: (TDDatabase*)db docID: (NSString*)docID {
    return [self readDocumentBodyThen: ^TDStatus(TDBody *body) {
        if (![self query: @"new_edits"] || [self boolQuery: @"new_edits"]) {
            // Regular PUT:
            return [self update: db docID: docID body: body deleting: NO];
        } else {
            // PUT with new_edits=false -- forcible insertion of existing revision:
            TDRevision* rev = [[[TDRevision alloc] initWithBody: body] autorelease];
            if (!rev)
                return kTDStatusBadJSON;
            if (!$equal(rev.docID, docID) || !rev.revID)
                return kTDStatusBadID;
            NSArray* history = [TDDatabase parseCouchDBRevisionHistory: body.properties];
            return [_db forceInsert: rev revisionHistory: history source: nil];
        }
    }];
}


- (TDStatus) do_DELETE: (TDDatabase*)db docID: (NSString*)docID {
    return [self update: db docID: docID body: nil deleting: YES];
}


- (TDStatus) updateAttachment: (NSString*)attachment docID: (NSString*)docID body: (NSData*)body {
    TDStatus status;
    TDRevision* rev = [_db updateAttachment: attachment 
                                       body: body
                                       type: [_request valueForHTTPHeaderField: @"Content-Type"]
                                   encoding: kTDAttachmentEncodingNone
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


- (TDStatus) do_PUT: (TDDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    return [self updateAttachment: attachment
                            docID: docID
                             body: (_request.HTTPBody ?: [NSData data])];
}


- (TDStatus) do_DELETE: (TDDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    return [self updateAttachment: attachment
                            docID: docID
                             body: nil];
}


#pragma mark - VIEW QUERIES:


- (TDView*) compileView: (NSString*)viewName fromProperties: (NSDictionary*)viewProps {
    NSString* language = viewProps[@"language"] ?: @"javascript";
    NSString* mapSource = viewProps[@"map"];
    if (!mapSource)
        return nil;
    TDMapBlock mapBlock = [[TDView compiler] compileMapFunction: mapSource language: language];
    if (!mapBlock) {
        Warn(@"View %@ has unknown map function: %@", viewName, mapSource);
        return nil;
    }
    NSString* reduceSource = viewProps[@"reduce"];
    TDReduceBlock reduceBlock = NULL;
    if (reduceSource) {
        reduceBlock =[[TDView compiler] compileReduceFunction: reduceSource language: language];
        if (!reduceBlock) {
            Warn(@"View %@ has unknown reduce function: %@", viewName, reduceSource);
            return nil;
        }
    }
    
    TDView* view = [_db viewNamed: viewName];
    [view setMapBlock: mapBlock reduceBlock: reduceBlock version: @"1"];
    
    NSDictionary* options = $castIf(NSDictionary, viewProps[@"options"]);
    if ($equal(options[@"collation"], @"raw"))
        view.collation = kTDViewCollationRaw;
    return view;
}


- (TDStatus) queryDesignDoc: (NSString*)designDoc view: (NSString*)viewName keys: (NSArray*)keys {
    NSString* tdViewName = $sprintf(@"%@/%@", designDoc, viewName);
    TDView* view = [_db existingViewNamed: tdViewName];
    if (!view || !view.mapBlock) {
        // No TouchDB view is defined, or it hasn't had a map block assigned;
        // see if there's a CouchDB view definition we can compile:
        TDRevision* rev = [_db getDocumentWithID: [@"_design/" stringByAppendingString: designDoc]
                                      revisionID: nil];
        if (!rev)
            return kTDStatusNotFound;
        NSDictionary* views = $castIf(NSDictionary, rev[@"views"]);
        NSDictionary* viewProps = $castIf(NSDictionary, views[viewName]);
        if (!viewProps)
            return kTDStatusNotFound;
        // If there is a CouchDB view, see if it can be compiled from source:
        view = [self compileView: tdViewName fromProperties: viewProps];
        if (!view)
            return kTDStatusDBError;
    }
    
    TDQueryOptions options;
    if (![self getQueryOptions: &options])
        return kTDStatusBadRequest;
    if (keys)
        options.keys = keys;
    
    TDStatus status = [view updateIndex];
    if (status >= kTDStatusBadRequest)
        return status;
    SequenceNumber lastSequenceIndexed = view.lastSequenceIndexed;
    
    // Check for conditional GET and set response Etag header:
    if (!keys) {
        SequenceNumber eTag = options.includeDocs ? _db.lastSequence : lastSequenceIndexed;
        if ([self cacheWithEtag: $sprintf(@"%lld", eTag)])
            return kTDStatusNotModified;
    }

    NSArray* rows = [view queryWithOptions: &options status: &status];
    if (!rows)
        return status;
    id updateSeq = options.updateSeq ? @(lastSequenceIndexed) : nil;
    _response.bodyObject = $dict({@"rows", rows},
                                 {@"total_rows", @(rows.count)},
                                 {@"offset", @(options.skip)},
                                 {@"update_seq", updateSeq});
    return kTDStatusOK;
}


- (TDStatus) do_GET: (TDDatabase*)db designDocID: (NSString*)designDoc view: (NSString*)viewName {
    return [self queryDesignDoc: designDoc view: viewName keys: nil];
}


- (TDStatus) do_POST: (TDDatabase*)db designDocID: (NSString*)designDoc view: (NSString*)viewName {
    NSArray* keys = $castIf(NSArray, (self.bodyAsDictionary)[@"keys"]);
    if (!keys)
        return kTDStatusBadParam;
    return [self queryDesignDoc: designDoc view: viewName keys: keys];
}


- (TDStatus) do_POST_temp_view: (TDDatabase*)db {
    if (![[_request valueForHTTPHeaderField: @"Content-Type"] hasPrefix: @"application/json"])
        return kTDStatusUnsupportedType;
    TDBody* requestBody = [TDBody bodyWithJSON: _request.HTTPBody];
    if (!requestBody.isValidJSON)
        return kTDStatusBadJSON;
    NSDictionary* props = requestBody.properties;
    if (!props)
        return kTDStatusBadJSON;
    
    TDQueryOptions options;
    if (![self getQueryOptions: &options])
        return kTDStatusBadRequest;
    
    if ([self cacheWithEtag: $sprintf(@"%lld", _db.lastSequence)])  // conditional GET
        return kTDStatusNotModified;

    TDView* view = [self compileView: @"@@TEMPVIEW@@" fromProperties: props];
    if (!view)
        return kTDStatusDBError;
    @try {
        TDStatus status = [view updateIndex];
        if (status >= kTDStatusBadRequest)
            return status;
        if (view.reduceBlock)
            options.reduce = YES;
        NSArray* rows = [view queryWithOptions: &options status: &status];
        if (!rows)
            return status;
        id updateSeq = options.updateSeq ? @(view.lastSequenceIndexed) : nil;
        _response.bodyObject = $dict({@"rows", rows},
                                     {@"total_rows", @(rows.count)},
                                     {@"offset", @(options.skip)},
                                     {@"update_seq", updateSeq});
        return kTDStatusOK;
    } @finally {
        [view deleteView];
    }
}


@end
