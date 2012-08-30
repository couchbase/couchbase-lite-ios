//
//  TDRouter_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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
#import "TDBody.h"
#import "TDServer.h"
#import "TDBase64.h"
#import "TDInternal.h"
#import "Test.h"
#import "TDJSON.h"


#if DEBUG
#pragma mark - TESTS


static TDDatabaseManager* createDBManager(void) {
    return [TDDatabaseManager createEmptyAtTemporaryPath: @"TDRouterTest"];
}


static TDResponse* SendRequest(TDDatabaseManager* server, NSString* method, NSString* path,
                               NSDictionary* headers, id bodyObj) {
    NSURL* url = [NSURL URLWithString: [@"touchdb://" stringByAppendingString: path]];
    CAssert(url, @"Invalid URL: <%@>", path);
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    for (NSString* header in headers)
        [request setValue: headers[header] forHTTPHeaderField: header];
    if (bodyObj) {
        if ([bodyObj isKindOfClass: [NSData class]])
            request.HTTPBody = bodyObj;
        else {
            NSError* error = nil;
            request.HTTPBody = [TDJSON dataWithJSONObject: bodyObj options:0 error:&error];
            CAssertNil(error);
        }
    }
    TDRouter* router = [[[TDRouter alloc] initWithDatabaseManager: server request: request] autorelease];
    CAssert(router!=nil);
    __block TDResponse* response = nil;
    __block NSUInteger dataLength = 0;
    __block BOOL calledOnFinished = NO;
    router.onResponseReady = ^(TDResponse* theResponse) {CAssert(!response); response = theResponse;};
    router.onDataAvailable = ^(NSData* data, BOOL finished) {dataLength += data.length;};
    router.onFinished = ^{CAssert(!calledOnFinished); calledOnFinished = YES;};
    [router start];
    CAssert(response);
    CAssertEq(dataLength, response.body.asJSON.length);
    CAssert(calledOnFinished);
    return response;
}

static id ParseJSONResponse(TDResponse* response) {
    NSData* json = response.body.asJSON;
    NSString* jsonStr = nil;
    id result = nil;
    if (json) {
        jsonStr = [[[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding] autorelease];
        CAssert(jsonStr);
        NSError* error;
        result = [TDJSON JSONObjectWithData: json options: 0 error: &error];
        CAssert(result, @"Couldn't parse JSON response: %@", error);
    }
    return result;
}

static TDResponse* sLastResponse;

static id SendBody(TDDatabaseManager* server, NSString* method, NSString* path, id bodyObj,
                   TDStatus expectedStatus, id expectedResult) {
    sLastResponse = SendRequest(server, method, path, nil, bodyObj);
    id result = ParseJSONResponse(sLastResponse);
    Log(@"%@ %@ --> %d", method, path, sLastResponse.status);
    
    CAssertEq(sLastResponse.internalStatus, expectedStatus);

    if (expectedResult)
        CAssertEqual(result, expectedResult);
    return result;
}

static id Send(TDDatabaseManager* server, NSString* method, NSString* path,
               int expectedStatus, id expectedResult) {
    return SendBody(server, method, path, nil, expectedStatus, expectedResult);
}

static void CheckCacheable(TDDatabaseManager* server, NSString* path) {
    NSString* eTag = (sLastResponse.headers)[@"Etag"];
    CAssert(eTag.length > 0, @"Missing eTag in response for %@", path);
    sLastResponse = SendRequest(server, @"GET", path, $dict({@"If-None-Match", eTag}), nil);
    CAssertEq(sLastResponse.status, kTDStatusNotModified);
}


TestCase(TDRouter_Server) {
    RequireTestCase(TDDatabaseManager);
    TDDatabaseManager* server = createDBManager();
    Send(server, @"GET", @"/", kTDStatusOK, $dict({@"TouchDB", @"Welcome"},
                                          {@"couchdb", @"Welcome"},
                                          {@"version", [TDRouter versionString]}));
    Send(server, @"GET", @"/_all_dbs", kTDStatusOK, @[]);
    Send(server, @"GET", @"/non-existent", kTDStatusNotFound, nil);
    Send(server, @"GET", @"/BadName", kTDStatusBadID, nil);
    Send(server, @"PUT", @"/", kTDStatusBadRequest, nil);
    NSDictionary* response = Send(server, @"POST", @"/", kTDStatusBadRequest, nil);
    
    CAssertEqual(response[@"status"], @(400));
    CAssertEqual(response[@"error"], @"bad request");
    
    NSDictionary* session = Send(server, @"GET", @"/_session", kTDStatusOK, nil);
    CAssert(session[@"ok"]);
    [server close];
}


TestCase(TDRouter_Databases) {
    RequireTestCase(TDRouter_Server);
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/database", kTDStatusCreated, nil);
    
    NSDictionary* dbInfo = Send(server, @"GET", @"/database", kTDStatusOK, nil);
    CAssertEq([dbInfo[@"doc_count"] intValue], 0);
    CAssertEq([dbInfo[@"update_seq"] intValue], 0);
    CAssert([dbInfo[@"disk_size"] intValue] > 8000);
    
    Send(server, @"PUT", @"/database", kTDStatusDuplicate, nil);
    Send(server, @"PUT", @"/database2", kTDStatusCreated, nil);
    Send(server, @"GET", @"/_all_dbs", kTDStatusOK, @[@"database", @"database2"]);
    dbInfo = Send(server, @"GET", @"/database2", kTDStatusOK, nil);
    CAssertEqual(dbInfo[@"db_name"], @"database2");
    Send(server, @"DELETE", @"/database2", kTDStatusOK, nil);
    Send(server, @"GET", @"/_all_dbs", kTDStatusOK, @[@"database"]);

    Send(server, @"PUT", @"/database%2Fwith%2Fslashes", kTDStatusCreated, nil);
    dbInfo = Send(server, @"GET", @"/database%2Fwith%2Fslashes", kTDStatusOK, nil);
    CAssertEqual(dbInfo[@"db_name"], @"database/with/slashes");
    [server close];
}


TestCase(TDRouter_Docs) {
    RequireTestCase(TDRouter_Databases);
    // PUT:
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    kTDStatusCreated, nil);
    NSString* revID = result[@"rev"];
    CAssert([revID hasPrefix: @"1-"]);

    // PUT to update:
    result = SendBody(server, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID}), 
                      kTDStatusCreated, nil);
    Log(@"PUT returned %@", result);
    revID = result[@"rev"];
    CAssert([revID hasPrefix: @"2-"]);
    
    Send(server, @"GET", @"/db/doc1", kTDStatusOK,
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"goodbye"}));
    CheckCacheable(server, @"/db/doc1");
    
    // Add more docs:
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"hello"}), 
                                    kTDStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hello"}), 
                                    kTDStatusCreated, nil);
    NSString* revID2 = result[@"rev"];

    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", kTDStatusOK, nil);
    CAssertEqual(result[@"total_rows"], @3);
    CAssertEqual(result[@"offset"], @0);
    NSArray* rows = result[@"rows"];
    CAssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));
    CheckCacheable(server, @"/db/_all_docs");

    // DELETE:
    result = Send(server, @"DELETE", $sprintf(@"/db/doc1?rev=%@", revID), kTDStatusOK, nil);
    revID = result[@"rev"];
    CAssert([revID hasPrefix: @"3-"]);

    Send(server, @"GET", @"/db/doc1", kTDStatusDeleted, nil);
    
    // _changes:
    Send(server, @"GET", @"/db/_changes", kTDStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc3"},
                                         {@"changes", $array($dict({@"rev", revID3}))},
                                         {@"seq", @3}),
                                   $dict({@"id", @"doc2"},
                                         {@"changes", $array($dict({@"rev", revID2}))},
                                         {@"seq", @4}),
                                   $dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revID}))},
                                         {@"seq", @5},
                                         {@"deleted", $true}))}));
    CheckCacheable(server, @"/db/_changes");
    
    // _changes with ?since:
    Send(server, @"GET", @"/db/_changes?since=4", kTDStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revID}))},
                                         {@"seq", @5},
                                         {@"deleted", $true}))}));
    Send(server, @"GET", @"/db/_changes?since=5", kTDStatusOK,
         $dict({@"last_seq", @5},
               {@"results", @[]}));
    [server close];
}


TestCase(TDRouter_LocalDocs) {
    RequireTestCase(TDDatabase_LocalDocs);
    RequireTestCase(TDRouter_Docs);
    // PUT a local doc:
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/_local/doc1", $dict({@"message", @"hello"}), 
                                    kTDStatusCreated, nil);
    NSString* revID = result[@"rev"];
    CAssert([revID hasPrefix: @"1-"]);
    
    // GET it:
    Send(server, @"GET", @"/db/_local/doc1", kTDStatusOK,
         $dict({@"_id", @"_local/doc1"},
               {@"_rev", revID},
               {@"message", @"hello"}));
    CheckCacheable(server, @"/db/_local/doc1");

    // Local doc should not appear in _changes feed:
    Send(server, @"GET", @"/db/_changes", kTDStatusOK,
         $dict({@"last_seq", @0},
               {@"results", @[]}));
    [server close];
}


TestCase(TDRouter_AllDocs) {
    // PUT:
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    
    NSDictionary* result;
    result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kTDStatusCreated, nil);
    NSString* revID = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kTDStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kTDStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", kTDStatusOK, nil);
    CAssertEqual(result[@"total_rows"], @3);
    CAssertEqual(result[@"offset"], @0);
    NSArray* rows = result[@"rows"];
    CAssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));
    
    // ?include_docs:
    result = Send(server, @"GET", @"/db/_all_docs?include_docs=true", kTDStatusOK, nil);
    CAssertEqual(result[@"total_rows"], @3);
    CAssertEqual(result[@"offset"], @0);
    rows = result[@"rows"];
    CAssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})},
                                    {@"doc", $dict({@"message", @"hello"},
                                                   {@"_id", @"doc1"}, {@"_rev", revID} )}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})},
                                    {@"doc", $dict({@"message", @"guten tag"},
                                                   {@"_id", @"doc2"}, {@"_rev", revID2} )}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})},
                                    {@"doc", $dict({@"message", @"bonjour"},
                                                   {@"_id", @"doc3"}, {@"_rev", revID3} )})
                              ));
    [server close];
}


TestCase(TDRouter_Views) {
    // PUT:
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    
    SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kTDStatusCreated, nil);
    SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kTDStatusCreated, nil);
    SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kTDStatusCreated, nil);
    
    TDDatabase* db = [server databaseNamed: @"db"];
    TDView* view = [db viewNamed: @"design/view"];
    [view setMapBlock: ^(NSDictionary* doc, TDMapEmitBlock emit) {
        if (doc[@"message"])
            emit(doc[@"message"], nil);
    } reduceBlock: NULL version: @"1"];

    // Query the view and check the result:
    Send(server, @"GET", @"/db/_design/design/_view/view", kTDStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}),
                                $dict({@"id", @"doc2"}, {@"key", @"guten tag"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @3}));
    
    // Check the ETag:
    TDResponse* response = SendRequest(server, @"GET", @"/db/_design/design/_view/view", nil, nil);
    NSString* etag = (response.headers)[@"Etag"];
    CAssertEqual(etag, $sprintf(@"\"%lld\"", view.lastSequenceIndexed));
    
    // Try a conditional GET:
    response = SendRequest(server, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    CAssertEq(response.status, kTDStatusNotModified);

    // Update the database:
    SendBody(server, @"PUT", @"/db/doc4", $dict({@"message", @"aloha"}), kTDStatusCreated, nil);
    
    // Try a conditional GET:
    response = SendRequest(server, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    CAssertEq(response.status, kTDStatusOK);
    CAssertEqual(ParseJSONResponse(response)[@"total_rows"], @4);
    [server close];
}


TestCase(TDRouter_ContinuousChanges) {
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);

    SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kTDStatusCreated, nil);

    __block TDResponse* response = nil;
    __block NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    NSURL* url = [NSURL URLWithString: @"touchdb:///db/_changes?feed=continuous"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    TDRouter* router = [[TDRouter alloc] initWithDatabaseManager: server request: request];
    router.onResponseReady = ^(TDResponse* routerResponse) {
        CAssert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content, BOOL finished) {
        [body appendData: content];
    };
    router.onFinished = ^{
        CAssert(!finished);
        finished = YES;
    };
    
    // Start:
    [router start];
    
    // Should initially have a response and one line of output:
    CAssert(response != nil);
    CAssertEq(response.status, kTDStatusOK);
    CAssert(body.length > 0);
    CAssert(!finished);
    [body setLength: 0];
    
    // Now make a change to the database:
    SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hej"}), kTDStatusCreated, nil);

    // Should now have received additional output from the router:
    CAssert(body.length > 0);
    CAssert(!finished);
    
    [router stop];
    [router release];
    [server close];
}


static NSDictionary* createDocWithAttachments(TDDatabaseManager* server,
                                              NSData* attach1, NSData* attach2) {
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    NSString* base64 = [TDBase64 encode: attach1];
    NSString* base642 = [TDBase64 encode: attach2];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})},
                                         {@"path/to/attachment",
                                                     $dict({@"content_type", @"text/plain"},
                                                           {@"data", base642})});
    NSDictionary* props = $dict({@"message", @"hello"},
                                {@"_attachments", attachmentDict});

    return SendBody(server, @"PUT", @"/db/doc1", props, kTDStatusCreated, nil);
}


TestCase(TDRouter_GetAttachment) {
    TDDatabaseManager* server = createDBManager();

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* result = createDocWithAttachments(server, attach1, attach2);
    NSString* revID = result[@"rev"];

    // Now get the attachment via its URL:
    TDResponse* response = SendRequest(server, @"GET", @"/db/doc1/attach", nil, nil);
    CAssertEq(response.status, kTDStatusOK);
    CAssertEqual(response.body.asJSON, attach1);
    CAssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    NSString* eTag = (response.headers)[@"Etag"];
    CAssert(eTag.length > 0);
    
    // Ditto the 2nd attachment, whose name contains "/"s:
    response = SendRequest(server, @"GET", @"/db/doc1/path/to/attachment", nil, nil);
    CAssertEq(response.status, kTDStatusOK);
    CAssertEqual(response.body.asJSON, attach2);
    CAssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    eTag = (response.headers)[@"Etag"];
    CAssert(eTag.length > 0);
    
    // A nonexistent attachment should result in a kTDStatusNotFound:
    response = SendRequest(server, @"GET", @"/db/doc1/bogus", nil, nil);
    CAssertEq(response.status, kTDStatusNotFound);
    
    response = SendRequest(server, @"GET", @"/db/missingdoc/bogus", nil, nil);
    CAssertEq(response.status, kTDStatusNotFound);
    
    // Get the document with attachment data:
    response = SendRequest(server, @"GET", @"/db/doc1?attachments=true", nil, nil);
    CAssertEq(response.status, kTDStatusOK);
    CAssertEqual((response.body)[@"_attachments"],
                 $dict({@"attach", $dict({@"data", [TDBase64 encode: attach1]}, 
                                        {@"content_type", @"text/plain"},
                                        {@"length", @(attach1.length)},
                                        {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                         {@"revpos", @1})},
                       {@"path/to/attachment", $dict({@"data", [TDBase64 encode: attach2]}, 
                                         {@"content_type", @"text/plain"},
                                         {@"length", @(attach2.length)},
                                         {@"digest", @"sha1-IrXQo0jpePvuKPv5nswnenqsIMc="},
                                         {@"revpos", @1})}));

    // Update the document but not the attachments:
    NSDictionary *attachmentDict, *props;
    attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                             {@"stub", $true})},
                           {@"path/to/attachment",
                               $dict({@"content_type", @"text/plain"},
                                     {@"stub", $true})});
    props = $dict({@"_rev", revID},
                  {@"message", @"aloha"},
                  {@"_attachments", attachmentDict});
    result = SendBody(server, @"PUT", @"/db/doc1", props, kTDStatusCreated, nil);
    revID = result[@"rev"];
    
    // Get the doc with attachments modified since rev #1:
    NSString* path = $sprintf(@"/db/doc1?attachments=true&atts_since=[%%22%@%%22]", revID);
    Send(server, @"GET", path, kTDStatusOK, 
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"aloha"},
               {@"_attachments", $dict({@"attach", $dict({@"stub", $true}, 
                                                         {@"content_type", @"text/plain"},
                                                         {@"length", @(attach1.length)},
                                                         {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                                         {@"revpos", @1})},
                                       {@"path/to/attachment", $dict({@"stub", $true}, 
                                                                     {@"content_type", @"text/plain"},
                                                                     {@"length", @(attach2.length)},
                                                                     {@"digest", @"sha1-IrXQo0jpePvuKPv5nswnenqsIMc="},
                                                                     {@"revpos", @1})})}));
    [server close];
}


TestCase(TDRouter_GetRange) {
    TDDatabaseManager* server = createDBManager();

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    createDocWithAttachments(server, attach1, attach2);

    TDResponse* response = SendRequest(server, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=5-15"}),
                                       nil);
    CAssertEq(response.status, 206);
    CAssertEqual((response.headers)[@"Content-Range"], @"bytes 5-15/27");
    CAssertEqual(response.body.asJSON, [@"is the body" dataUsingEncoding: NSUTF8StringEncoding]);

    response = SendRequest(server, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=12-"}),
                                       nil);
    CAssertEq(response.status, 206);
    CAssertEqual((response.headers)[@"Content-Range"], @"bytes 12-26/27");
    CAssertEqual(response.body.asJSON, [@"body of attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    response = SendRequest(server, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=-7"}),
                                       nil);
    CAssertEq(response.status, 206);
    CAssertEqual((response.headers)[@"Content-Range"], @"bytes 20-26/27");
    CAssertEqual(response.body.asJSON, [@"attach1" dataUsingEncoding: NSUTF8StringEncoding]);
}


TestCase(TDRouter_PutMultipart) {
    RequireTestCase(TDRouter_Docs);
    RequireTestCase(TDMultipartDownloader);
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"length", @(36)},
                                                           {@"content_type", @"text/plain"},
                                                           {@"follows", $true})});
    NSDictionary* props = $dict({@"message", @"hello"},
                                {@"_attachments", attachmentDict});
    NSString* attachmentString = @"This is the value of the attachment.";

    NSString* body = $sprintf(@"\r\n--BOUNDARY\r\n\r\n"
                              "%@"
                              "\r\n--BOUNDARY\r\n"
                              "Content-Disposition: attachment; filename=attach\r\n"
                              "Content-Type: text/plain\r\n\r\n"
                              "%@"
                              "\r\n--BOUNDARY--",
                              [TDJSON stringWithJSONObject: props options: 0 error: NULL],
                              attachmentString);
    
    TDResponse* response = SendRequest(server, @"PUT", @"/db/doc",
                           $dict({@"Content-Type", @"multipart/related; boundary=\"BOUNDARY\""}),
                                       [body dataUsingEncoding: NSUTF8StringEncoding]);
    CAssertEq(response.status, kTDStatusCreated);
}


TestCase(TDRouter_OpenRevs) {
    RequireTestCase(TDRouter_Databases);
    // PUT:
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    kTDStatusCreated, nil);
    NSString* revID1 = result[@"rev"];
    
    // PUT to update:
    result = SendBody(server, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID1}), 
                      kTDStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    Send(server, @"GET", @"/db/doc1?open_revs=all", kTDStatusOK,
         $array( $dict({@"ok", $dict({@"_id", @"doc1"},
                                     {@"_rev", revID2},
                                     {@"message", @"goodbye"})}) ));
    Send(server, @"GET", $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, revID2), kTDStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID2},
                                    {@"message", @"goodbye"})})
                ));
    Send(server, @"GET", $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, @"bogus"), kTDStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"missing", @"bogus"})
                ));
    [server close];
}


TestCase(TDRouter_RevsDiff) {
    RequireTestCase(TDRouter_Databases);
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    NSDictionary* doc1r1 = SendBody(server, @"PUT", @"/db/11111", $dict(), kTDStatusCreated,nil);
    NSString* doc1r1ID = doc1r1[@"rev"];
    NSDictionary* doc2r1 = SendBody(server, @"PUT", @"/db/22222", $dict(), kTDStatusCreated,nil);
    NSString* doc2r1ID = doc2r1[@"rev"];
    NSDictionary* doc3r1 = SendBody(server, @"PUT", @"/db/33333", $dict(), kTDStatusCreated,nil);
    NSString* doc3r1ID = doc3r1[@"rev"];
    
    NSDictionary* doc1r2 = SendBody(server, @"PUT", @"/db/11111", $dict({@"_rev", doc1r1ID}), kTDStatusCreated,nil);
    NSString* doc1r2ID = doc1r2[@"rev"];
    SendBody(server, @"PUT", @"/db/22222", $dict({@"_rev", doc2r1ID}), kTDStatusCreated,nil);

    NSDictionary* doc1r3 = SendBody(server, @"PUT", @"/db/11111", $dict({@"_rev", doc1r2ID}), kTDStatusCreated,nil);
    NSString* doc1r3ID = doc1r3[@"rev"];
    
    SendBody(server, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"3-foo"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-bar"]},
                   {@"99999", @[@"6-six"]}),
             kTDStatusOK,
             $dict({@"11111", $dict({@"missing", @[@"3-foo"]},
                                    {@"possible_ancestors", @[doc1r2ID, doc1r1ID]})},
                   {@"33333", $dict({@"missing", @[@"10-bar"]},
                                    {@"possible_ancestors", @[doc3r1ID]})},
                   {@"99999", $dict({@"missing", @[@"6-six"]})}
                   ));
    
    // Compact the database -- this will null out the JSON of doc1r1 & doc1r2,
    // and they won't be returned as possible ancestors anymore.
    Send(server, @"POST", @"/db/_compact", kTDStatusAccepted, nil);
    
    SendBody(server, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"4-foo"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-bar"]},
                   {@"99999", @[@"6-six"]}),
             kTDStatusOK,
             $dict({@"11111", $dict({@"missing", @[@"4-foo"]},
                                    {@"possible_ancestors", @[doc1r3ID]})},
                   {@"33333", $dict({@"missing", @[@"10-bar"]},
                                    {@"possible_ancestors", @[doc3r1ID]})},
                   {@"99999", $dict({@"missing", @[@"6-six"]})}
                   ));

    // Check the revision history using _revs_info:
    Send(server, @"GET", @"/db/11111?revs_info=true", 200,
          @{ @"_id" : @"11111", @"_rev": doc1r3ID,
             @"_revs_info": @[ @{ @"rev" : doc1r3ID, @"status": @"available" },
                               @{ @"rev" : doc1r2ID, @"status": @"missing" },
                               @{ @"rev" : doc1r1ID, @"status": @"missing" }
         ]});

    // Check the revision history using _revs:
    Send(server, @"GET", @"/db/11111?revs=true", 200,
         @{ @"_id" : @"11111", @"_rev": doc1r3ID,
            @"_revisions": @{
                @"start": @3,
                @"ids": @[ [doc1r3ID substringFromIndex: 2], [doc1r2ID substringFromIndex: 2],
                           [doc1r1ID substringFromIndex: 2] ]
         } } );

    [server close];
}


TestCase(TDRouter_AccessCheck) {
    RequireTestCase(TDRouter_Databases);
    TDDatabaseManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kTDStatusCreated, nil);
    
    NSURL* url = [NSURL URLWithString: @"touchdb:///db/"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = @"GET";
    TDRouter* router = [[[TDRouter alloc] initWithDatabaseManager: server request: request] autorelease];
    CAssert(router!=nil);
    __block BOOL calledOnAccessCheck = NO;
    router.onAccessCheck = ^TDStatus(TDDatabase* accessDB, NSString* docID, SEL action) {
        CAssert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 200;
    };
    [router start];
    CAssert(calledOnAccessCheck);
    CAssert(router.response.status == 200);
    
    router = [[[TDRouter alloc] initWithDatabaseManager: server request: request] autorelease];
    CAssert(router!=nil);
    calledOnAccessCheck = NO;
    router.onAccessCheck = ^TDStatus(TDDatabase* accessDB, NSString* docID, SEL action) {
        CAssert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 401;
    };
    [router start];
    
    CAssert(calledOnAccessCheck);
    CAssert(router.response.status == 401);
}


TestCase(TDRouter) {
    RequireTestCase(TDRouter_Server);
    RequireTestCase(TDRouter_Databases);
    RequireTestCase(TDRouter_Docs);
    RequireTestCase(TDRouter_AllDocs);
    RequireTestCase(TDRouter_ContinuousChanges);
    RequireTestCase(TDRouter_GetAttachment);
    RequireTestCase(TDRouter_RevsDiff);
    RequireTestCase(TDRouter_AccessCheck);
}

#endif
