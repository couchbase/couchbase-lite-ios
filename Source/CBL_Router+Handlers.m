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
#import "CBLDatabase+Replication.h"
#import "CBLView+Internal.h"
#import "CBLQueryRow+Router.h"
#import "CBL_Body.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLMultipartDocumentReader.h"
#import "CBLMultipartWriter.h"
#import "CBL_Revision.h"
#import "CBLDatabaseChange.h"
#import "CBL_Server.h"
#import "CBLPersonaAuthorizer.h"
#import "CBLFacebookAuthorizer.h"
#import "CBL_Replicator.h"
#import "CBL_Attachment.h"
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
    UInt64 num_docs = db.documentCount;
    SequenceNumber update_seq = db.lastSequenceNumber;
    if (num_docs == NSNotFound || update_seq == NSNotFound)
        return kCBLStatusDBError;
    UInt64 startTime = (UInt64)(db.startTime.timeIntervalSince1970 * 1.0e6); // it's in microseconds
    _response.bodyObject = $dict({@"db_name", db.name},
                                 {@"db_uuid", db.publicUUID},
                                 {@"doc_count", @(num_docs)},
                                 {@"update_seq", @(update_seq)},
                                 {@"committed_update_seq", @(update_seq)},
                                 {@"purge_seq", @(0)}, // TODO: Implement
                                 {@"disk_size", @(db.totalDataSize)},
                                 {@"instance_start_time", @(startTime)});
    return kCBLStatusOK;
}


- (CBLStatus) do_PUT: (CBLDatabase*)db {
    if (db.exists)
        return kCBLStatusDuplicate;
    NSError* error;
    if (![db open: &error])
        return CBLStatusFromNSError(error, 0);
    [self setResponseLocation: _request.URL];
    return kCBLStatusCreated;
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db {
    if ([self query: @"rev"])
        return kCBLStatusBadID;  // CouchDB checks for this; probably meant to be a document deletion
    if (!db.exists)
        return kCBLStatusNotFound;
    else if (![db deleteDatabase: NULL])
        return kCBLStatusServerError;
    return kCBLStatusOK;
}


- (CBLStatus) do_POST_purge: (CBLDatabase*)db {
    // <http://wiki.apache.org/couchdb/Purge_Documents>
    NSDictionary* body = self.bodyAsDictionary;
    if (!body)
        return kCBLStatusBadJSON;
    NSDictionary* purgedDocs;
    CBLStatus status = [db.storage purgeRevisions: body result: &purgedDocs];
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

- (NSArray*) queryIteratorAllRows: (CBLQueryEnumerator*) iterator
{
    CBLContentOptions options = self.contentOptions;
    NSMutableArray* result = $marray();
    CBLQueryRow* row;
    while (nil != (row = iterator.nextObject)) {
        NSDictionary* dict = row.asJSONDictionary;
        if (options != 0) {
            NSDictionary* doc = dict[@"doc"];
            if (doc) {
                // Add content options:
                CBL_Revision* rev = [CBL_Revision revisionWithProperties: doc];
                CBLStatus status;
                rev = [self applyOptions: options toRevision: rev status: &status];
                if (rev) {
                    NSMutableDictionary* mdict = [dict mutableCopy];
                    mdict[@"doc"] = rev.properties;
                    dict = mdict;
                }
            }
        }
        [result addObject: dict];
    }
    return result;
}

- (CBLStatus) doAllDocs: (CBLQueryOptions*)options
{
    CBLStatus status;
    CBLQueryEnumerator* iterator = [_db getAllDocs: options status: &status];
    if (!iterator)
        return status;
    NSArray* result = [self queryIteratorAllRows: iterator];
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

    return [_db.storage inTransaction: ^CBLStatus {
        NSMutableArray* results = [NSMutableArray arrayWithCapacity: docs.count];
        for (NSDictionary* doc in docs) {
            @autoreleasepool {
                NSString* docID = doc.cbl_id;
                CBL_Revision* rev;
                CBLStatus status;
                NSError* error;
                CBL_Body* docBody = [CBL_Body bodyWithProperties: doc];
                if (noNewEdits) {
                    rev = [[CBL_Revision alloc] initWithBody: docBody];
                    NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: doc];
                    status = rev ? [db forceInsert: rev
                                   revisionHistory: history
                                            source: self.source
                                             error: &error] : kCBLStatusBadParam;
                } else {
                    status = [self update: db
                                    docID: docID
                                     body: docBody
                                 deleting: NO
                            allowConflict: allOrNothing
                               createdRev: &rev
                                    error: &error];
                }

                NSDictionary* result = nil;
                if (status < 300) {
                    Assert(rev.revID);
                    if (!noNewEdits)
                        result = $dict({@"id", rev.docID}, {@"rev", rev.revID}, {@"ok", $true});
                } else if (status >= 500) {
                    return status;  // abort the whole thing if something goes badly wrong
                } else if (allOrNothing) {
                    if (error)
                        _response.statusReason = error.localizedFailureReason;
                    return status;  // all_or_nothing backs out if there's any error
                } else {
                    NSString* errorMessage = nil;
                    status = CBLStatusToHTTPStatus(status, &errorMessage);
                    NSString* reason = error.localizedFailureReason;
                    if (reason)
                        result = $dict({@"id", docID}, {@"error", errorMessage}, {@"reason", reason}, {@"status", @(status)});
                    else
                        result = $dict({@"id", docID}, {@"error", errorMessage}, {@"status", @(status)});
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
    CBLStatus status;
    if (![db.storage findMissingRevisions: revs status: &status])
        return status;
    
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
        NSArray* ancestors = [_db.storage getPossibleAncestorRevisionIDs: rev limit: 0
                                                         onlyAttachments: NO];
        if (ancestors.count > 0)
            docInfo[@"possible_ancestors"] = ancestors;
    }
                                    
    _response.bodyObject = diffs;
    return kCBLStatusOK;
}


- (CBLStatus) do_POST_compact: (CBLDatabase*)db {
    if ([db compact: NULL])
        return kCBLStatusAccepted;   // CouchDB returns 202 'cause it's async
    else
        return kCBLStatusDBError;
}

- (CBLStatus) do_POST_ensure_full_commit: (CBLDatabase*)db {
    return kCBLStatusOK;
}


#pragma mark - REPLICATION & ACTIVE TASKS


- (CBLStatus) do_POST_replicate {
    NSDictionary* body = self.bodyAsDictionary;
    CBLStatus status;
    id<CBL_Replicator> repl = [_dbManager replicatorWithProperties: body status: &status];
    if (!repl)
        return status;

    if ([$castIf(NSNumber, body[@"cancel"]) boolValue]) {
        // Cancel replication:
        if (repl.status == kCBLReplicatorStopped)
            return kCBLStatusNotFound;
        [repl stop];
        return kCBLStatusOK;
    } else {
        // Start replication:
        [repl start];
        if (repl.settings.continuous || [$castIf(NSNumber, body[@"async"]) boolValue]) {
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
    id<CBL_Replicator> repl = n.object;
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
        for (id<CBL_Replicator> repl in db.activeReplicators) {
            [activity addObject: [self activeTaskInfo: repl]];
        }
    }

    [self parseChangesMode];
    if (_changesMode >= kContinuousFeed) {
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
    id<CBL_Replicator> repl = n.object;
    if (repl.db.manager == _dbManager)
        [self sendContinuousLine: [self activeTaskInfo: repl]];
}


- (NSDictionary*) activeTaskInfo: (id<CBL_Replicator>)repl {
    static NSString* const kStatusName[] = {@"Stopped", @"Offline", @"Idle", @"Active"};
    // For schema, see http://wiki.apache.org/couchdb/HttpGetActiveTasks
    NSString* source = repl.settings.remote.absoluteString;
    NSString* target = _db.name;
    if (repl.settings.isPush) {
        NSString* temp = source;
        source = target;
        target = temp;
    }
    NSString* status;
    id progress = nil;
    if (repl.status == kCBLReplicatorActive) {
        NSUInteger processed = repl.changesProcessed;
        NSUInteger total = repl.changesTotal;
        status = $sprintf(@"Processed %u / %u changes",
                          (unsigned)processed, (unsigned)total);
        progress = (total>0) ? @(lroundf(100*(processed / (float)total))) : nil;
    } else {
        status = kStatusName[repl.status];
    }
    NSArray* error = nil;
    NSError* errorObj = repl.error;
    if (errorObj)
        error = @[@(errorObj.code), errorObj.localizedDescription];

    NSArray* activeRequests = nil;
    if ([repl respondsToSelector: @selector(activeTasksInfo)])
        activeRequests = repl.activeTasksInfo;
    
    return $dict({@"type", @"Replication"},
                 {@"task", repl.sessionID},
                 {@"source", source},
                 {@"target", target},
                 {@"continuous", (repl.settings.continuous ? $true : nil)},
                 {@"status", status},
                 {@"progress", progress},
                 {@"x_active_requests", activeRequests},
                 {@"error", error});
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
            rev = [db.storage getLocalDocumentWithID: docID revisionID: revID];
        } else {
            includeAttachments = (options & kCBLIncludeAttachments) != 0;
            if (includeAttachments) {
                sendMultipart = !mustSendJSON;
                options &= ~kCBLIncludeAttachments;
            }
            CBLStatus status;
            rev = [db getDocumentWithID: docID revisionID: revID withBody: YES status: &status];
            if (rev)
                rev = [self applyOptions: options toRevision: rev status: &status];
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

        if (!isLocalDoc && includeAttachments) {
            int minRevPos = 1;
            NSArray* attsSince = parseJSONRevArrayQuery([self query: @"atts_since"]);
            NSString* ancestorID = [_db.storage findCommonAncestorOf: rev withRevIDs: attsSince];
            if (ancestorID)
                minRevPos = [CBL_Revision generationFromRevID: ancestorID] + 1;
            CBL_MutableRevision* expandedRev = rev.mutableCopy;
            CBLStatus status;
            if (![db expandAttachmentsIn: expandedRev
                               minRevPos: minRevPos
                            allowFollows: sendMultipart
                                  decode: ![self boolQuery: @"att_encoding_info"]
                                  status: &status])
                return status;
            rev = expandedRev;
        }

        if (sendMultipart)
            [_response setMultipartBody: [self multipartWriterForRevision: rev
                                                              contentType: @"multipart/related"]];
        else
            _response.body = rev.body;
        
    } else {
        // open_revs query:
        NSMutableArray* result;
        if ($equal(openRevsParam, @"all")) {
            // ?open_revs=all returns all current/leaf revisions:
            BOOL includeDeleted = [self boolQuery: @"include_deleted"];
            CBL_RevisionList* allRevs = [_db.storage getAllRevisionsOfDocumentID: docID
                                                                     onlyCurrent: YES];
            result = [NSMutableArray arrayWithCapacity: allRevs.count];
            for (CBL_Revision* rev in allRevs.allRevisions) {
                if (!includeDeleted && rev.deleted)
                    continue;
                CBLStatus status;
                CBL_Revision* loadedRev = [_db revisionByLoadingBody: rev status: &status];
                if (loadedRev)
                    loadedRev = [self applyOptions: options toRevision: loadedRev status: &status];
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
                                                 withBody: YES status: &status];
                if (rev)
                    rev = [self applyOptions: options toRevision: rev status: &status];
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


- (CBLMultipartWriter*) multipartWriterForRevision: (CBL_Revision*)rev
                                       contentType: (NSString*)contentType
{
    CBLMultipartWriter* writer = [[CBLMultipartWriter alloc] initWithContentType: contentType
                                                                        boundary: nil];
    [writer setNextPartsHeaders: @{@"Content-Type": @"application/json"}];
    [writer addData: rev.asJSON];
    NSDictionary* attachments = rev.attachments;
    for (NSString* attachmentName in attachments) {
        NSDictionary* attachment = attachments[attachmentName];
        if (attachment[@"follows"]) {
            NSString* disposition = $sprintf(@"attachment; filename=%@", CBLQuoteString(attachmentName));
            [writer setNextPartsHeaders: $dict({@"Content-Disposition", disposition})];

            CBLStatus status;
            CBL_Attachment* attachObj = [_db attachmentForDict: attachment named: attachmentName
                                                        status: &status];
            if (!attachObj)
                return nil;
            NSURL* fileURL = attachObj.contentURL;
            if (fileURL)
                [writer addFileURL: fileURL];
            else
                [writer addStream: attachObj.contentStream];
        }
    }
    return writer;
}


- (CBL_Revision*) applyOptions: (CBLContentOptions)options
                    toRevision: (CBL_Revision*)rev
                        status: (CBLStatus*)outStatus
{
    if (options & (kCBLIncludeRevs | kCBLIncludeRevsInfo | kCBLIncludeConflicts |
                   kCBLIncludeAttachments | kCBLIncludeLocalSeq)) {
        NSMutableDictionary* dst = [rev.properties mutableCopy];
        id<CBL_Storage> storage = _db.storage;

        if (options & kCBLIncludeLocalSeq) {
            dst[@"_local_seq"] = @(rev.sequence);
        }
        if (options & kCBLIncludeRevs) {
            NSArray* revs = [_db getRevisionHistory: rev backToRevIDs: nil];
            dst[@"_revisions"] = [CBLDatabase makeRevisionHistoryDict: revs];
        }
        if (options & kCBLIncludeRevsInfo) {
            NSArray* revs = [_db getRevisionHistory: rev backToRevIDs: nil];
            dst[@"_revs_info"] = [revs my_map: ^id(CBL_Revision* rev) {
                NSString* status = @"available";
                if (rev.deleted)
                    status = @"deleted";
                else if (rev.missing)
                    status = @"missing";
                return $dict({@"rev", [rev revID]}, {@"status", status});
            }];
        }
        if (options & kCBLIncludeConflicts) {
            CBL_RevisionList* revs = [storage getAllRevisionsOfDocumentID: rev.docID
                                                                  onlyCurrent: YES];
            if (revs.count > 1) {
                dst[@"_conflicts"] = [revs.allRevisions my_map: ^(id aRev) {
                    return ($equal(aRev, rev) || [(CBL_Revision*)aRev deleted]) ? nil : [aRev revID];
                }];
            }
        }
        CBL_MutableRevision* nuRev = [CBL_MutableRevision revisionWithProperties: dst];
        if (options & kCBLIncludeAttachments) {
            if (![_db expandAttachmentsIn: nuRev
                                minRevPos: 0
                             allowFollows: NO
                                   decode: ![self boolQuery: @"att_encoding_info"]
                                   status: outStatus])
                return nil;
        }
        rev = nuRev;
    }
    return rev;
}


- (CBLStatus) do_GET: (CBLDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachmentName {
    CBLStatus status;
    CBL_Revision* rev = [db getDocumentWithID: docID
                                 revisionID: [self query: @"rev"]  // often nil
                                     withBody: NO               // all we need is revID & sequence
                                       status: &status];
    if (!rev)
        return status;
    if ([self cacheWithEtag: rev.revID])        // set ETag and check conditional GET
        return kCBLStatusNotModified;
    
    NSString* acceptEncoding = [_request valueForHTTPHeaderField: @"Accept-Encoding"];
    BOOL acceptEncoded = (acceptEncoding
                          && [acceptEncoding rangeOfString: @"gzip"].length > 0
                          && [_request valueForHTTPHeaderField: @"Range"] == nil);

    CBL_Attachment* attachment = [_db attachmentForRevision: rev
                                                      named: attachmentName
                                                     status: &status];
    if (!attachment)
        return status;

    if ($equal(_request.HTTPMethod, @"HEAD")) {
        if (_local) {
            // Let in-app clients know the location of the attachment file:
            _response[@"Location"] = attachment.contentURL.absoluteString;
        }
        UInt64 length = attachment->length;
        if (acceptEncoded && attachment->encoding == kCBLAttachmentEncodingGZIP
                          && attachment->encodedLength)
            length = attachment->encodedLength;
        _response[@"Content-Length"] = $sprintf(@"%llu", length);
        
    } else {
        NSData* contents = acceptEncoded ? attachment.encodedContent : attachment.content;
        if (!contents)
            return kCBLStatusNotFound;
        _response.body = [CBL_Body bodyWithJSON: contents];   //FIX: This is a lie, it's not JSON
    }
    NSString* type = attachment.contentType;
    if (type)
        _response[@"Content-Type"] = type;
    if (acceptEncoding && attachment->encoding == kCBLAttachmentEncodingGZIP)
        _response[@"Content-Encoding"] = @"gzip";
    return kCBLStatusOK;
}


- (CBLStatus) update: (CBLDatabase*)db
               docID: (NSString*)docID
                body: (CBL_Body*)body
            deleting: (BOOL)deleting
       allowConflict: (BOOL)allowConflict
          createdRev: (CBL_Revision**)outRev
               error: (NSError**)outError
{
    if (body && !body.isValidJSON) {
        CBLStatusToOutNSError(kCBLStatusBadJSON, outError);
        return kCBLStatusBadJSON;
    }
    
    NSString* prevRevID;
    
    if (!deleting) {
        NSDictionary* properties = body.properties;
        deleting = properties.cbl_deleted;
        if (!docID) {
            // POST's doc ID may come from the _id field of the JSON body.
            docID = properties.cbl_id;
            if (!docID && deleting) {
                CBLStatusToOutNSError(kCBLStatusBadID, outError);
                return kCBLStatusBadID;
            }
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
    if (!rev) {
        CBLStatusToOutNSError(kCBLStatusBadID, outError);
        return kCBLStatusBadID;
    }
    rev.body = body;
    
    CBLStatus status;
    if ([docID hasPrefix: @"_local/"]) {
        *outRev = [db.storage putLocalRevision: rev
                                prevRevisionID: prevRevID
                                      obeyMVCC: YES
                                        status: &status];

        if (CBLStatusIsError(status)) {
            CBLStatusToOutNSError(status, outError);
        }
    } else
        *outRev = [db putDocID: docID
                    properties: [rev.properties mutableCopy]
                prevRevisionID: prevRevID
                 allowConflict: allowConflict
                        source: self.source
                        status: &status
                         error: outError];
    return status;
}


- (CBLStatus) update: (CBLDatabase*)db
               docID: (NSString*)docID
                body: (CBL_Body*)body
            deleting: (BOOL)deleting
               error: (NSError**)outError
{
    if (docID) {
        // On PUT/DELETE, get revision ID from either ?rev= query, If-Match: header, or doc body:
        NSString* revParam = [self query: @"rev"];
        NSString* ifMatch = [_request valueForHTTPHeaderField: @"If-Match"];
        if (ifMatch) {
            if (!revParam)
                revParam = ifMatch;
            else if (!$equal(revParam, ifMatch)) {
                CBLStatus status = kCBLStatusBadRequest;
                CBLStatusToOutNSError(status, outError);
                return status;
            }
        }
        if (revParam && body) {
            id revProp = body.properties.cbl_rev;
            if (!revProp) {
                // No _rev property in body, so use ?rev= query param instead:
                NSMutableDictionary* props = body.properties.mutableCopy;
                props[@"_rev"] = revParam;
                body = [CBL_Body bodyWithProperties: props];
            } else if (!$equal(revProp, revParam)) {
                // mismatch between _rev and rev
                CBLStatus status = kCBLStatusBadRequest;
                CBLStatusToOutNSError(status, outError);
                return status;
            }
        }
    }

    CBL_Revision* rev;
    CBLStatus status = [self update: db docID: docID body: body
                           deleting: deleting
                      allowConflict: NO
                         createdRev: &rev
                              error: outError];
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
            [self sendResponseHeaders];
            [self sendResponseBodyAndFinish: YES];
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
        NSError* error;
        CBLStatus status = [self update: db docID: nil body: body deleting: NO error: &error];
        _response.statusReason = error.localizedFailureReason;
        return status;
    }];
}


- (CBLStatus) do_PUT: (CBLDatabase*)db docID: (NSString*)docID {
    return [self readDocumentBodyThen: ^CBLStatus(CBL_Body *body) {
        if (![self query: @"new_edits"] || [self boolQuery: @"new_edits"]) {
            // Regular PUT:
            NSError* error;
            CBLStatus status = [self update: db docID: docID body: body deleting: NO error: &error];
            _response.statusReason = error.localizedFailureReason;
            return status;
        } else {
            // PUT with new_edits=false -- forcible insertion of existing revision:
            CBL_Revision* rev = [[CBL_Revision alloc] initWithBody: body];
            if (!rev)
                return kCBLStatusBadJSON;
            if (!$equal(rev.docID, docID) || !rev.revID)
                return kCBLStatusBadID;
            NSArray* history = [CBLDatabase parseCouchDBRevisionHistory: body.properties];
            NSError* error;
            CBLStatus status = [_db forceInsert: rev
                                revisionHistory: history
                                         source: self.source
                                          error: &error];
            if (!CBLStatusIsError(status)) {
                _response.bodyObject = $dict({@"ok", $true},
                                             {@"id", rev.docID},
                                             {@"rev", rev.revID});
            } else
                _response.statusReason = error.localizedFailureReason;

            return status;
        }
    }];
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db docID: (NSString*)docID {
    NSError* error;
    CBLStatus status = [self update: db docID: docID body: nil deleting: YES error: &error];
    _response.statusReason = error.localizedFailureReason;
    return status;
}


- (CBLStatus) updateAttachment: (NSString*)attachment
                        docID: (NSString*)docID
                          body: (CBL_BlobStoreWriter*)body
                         error: (NSError**)outError
{
    CBLStatus status;
    CBL_Revision* rev = [_db updateAttachment: attachment
                                         body: body
                                         type: [_request valueForHTTPHeaderField: @"Content-Type"]
                                     encoding: kCBLAttachmentEncodingNone
                                      ofDocID: docID
                                        revID: ([self query: @"rev"] ?: self.ifMatch)
                                       source: self.source
                                       status: &status
                                        error: outError];
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

    NSError* error;
    CBLStatus status = [self updateAttachment: attachment docID: docID body: blob error: &error];
    _response.statusReason = error.localizedFailureReason;
    return status;
}


- (CBLStatus) do_DELETE: (CBLDatabase*)db docID: (NSString*)docID attachment: (NSString*)attachment {
    NSError* error;
    CBLStatus status = [self updateAttachment: attachment docID: docID body: nil error: &error];
    _response.statusReason = error.localizedFailureReason;
    return status;
}


#pragma mark - VIEW QUERIES:


- (CBLStatus) queryDesignDoc: (NSString*)designDoc view: (NSString*)viewName keys: (NSArray*)keys {
    CBLView* view = [_db viewNamed: $sprintf(@"%@/%@", designDoc, viewName)];
    CBLStatus status = [view compileFromDesignDoc];
    if (CBLStatusIsError(status))
        return status;
    
    CBLQueryOptions *options = [self getQueryOptions];
    if (!options)
        return kCBLStatusBadRequest;
    if (keys)
        options.keys = keys;

    if (options->indexUpdateMode == kCBLUpdateIndexBefore || view.lastSequenceIndexed <= 0) {
        status = [view _updateIndex];
        if (status >= kCBLStatusBadRequest)
            return status;
    } else if (options->indexUpdateMode == kCBLUpdateIndexAfter &&
               view.lastSequenceIndexed < _db.lastSequenceNumber) {
        [_db doAsync:^{
            [view updateIndex];
        }];
    }
    
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
    CBLQueryEnumerator* iterator = [view _queryWithOptions: options status: &status];
    if (!iterator)
        return status;
    NSArray* rows = [self queryIteratorAllRows: iterator];
    id updateSeq = options->updateSeq ? @(view.lastSequenceIndexed) : nil;
    _response.bodyObject = $dict({@"rows", rows},
                                 {@"total_rows", @(view.currentTotalRows)},
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
    CBLStatus status = [view compileFromProperties: props language: @"javascript"];
    if (CBLStatusIsError(status))
        return status;

    @try {
        CBLStatus status = [view _updateIndex];
        if (status >= kCBLStatusBadRequest)
            return status;
        return [self queryView: view withOptions: options];
    } @finally {
        [view deleteView];
    }
}


@end
