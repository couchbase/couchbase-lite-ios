//
//  CBL_Router_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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
#import "CBL_Body.h"
#import "CBL_Server.h"
#import "CBLBase64.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "Test.h"
#import "CBLJSON.h"


#if DEBUG
#pragma mark - UTILITIES


static CBLManager* createDBManager(void) {
    return [CBLManager createEmptyAtTemporaryPath: @"CBL_RouterTest"];
}


static CBLResponse* SendRequest(CBLManager* server, NSString* method, NSString* path,
                               NSDictionary* headers, id bodyObj) {
    NSURL* url = [NSURL URLWithString: [@"cbl://" stringByAppendingString: path]];
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
            request.HTTPBody = [CBLJSON dataWithJSONObject: bodyObj options:0 error:&error];
            CAssertNil(error);
        }
    }
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: server request: request];
    CAssert(router!=nil);
    __block CBLResponse* response = nil;
    __block NSUInteger dataLength = 0;
    __block BOOL calledOnFinished = NO;
    router.onResponseReady = ^(CBLResponse* theResponse) {CAssert(!response); response = theResponse;};
    router.onDataAvailable = ^(NSData* data, BOOL finished) {dataLength += data.length;};
    router.onFinished = ^{CAssert(!calledOnFinished); calledOnFinished = YES;};
    [router start];
    CAssert(response);
    CAssertEq(dataLength, response.body.asJSON.length);
    CAssert(calledOnFinished);
    return response;
}

static id ParseJSONResponse(CBLResponse* response) {
    NSData* json = response.body.asJSON;
    NSString* jsonStr = nil;
    id result = nil;
    if (json) {
        jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
        CAssert(jsonStr);
        NSError* error;
        result = [CBLJSON JSONObjectWithData: json options: 0 error: &error];
        CAssert(result, @"Couldn't parse JSON response: %@", error);
    }
    return result;
}

static CBLResponse* sLastResponse;

static id SendBody(CBLManager* server, NSString* method, NSString* path, id bodyObj,
                   CBLStatus expectedStatus, id expectedResult) {
    sLastResponse = SendRequest(server, method, path, nil, bodyObj);
    id result = ParseJSONResponse(sLastResponse);
    Log(@"%@ %@ --> %d", method, path, sLastResponse.status);
    CAssert(result != nil);
    
    CAssertEq(sLastResponse.internalStatus, expectedStatus);

    if (expectedResult)
        CAssertEqual(result, expectedResult);
    return result;
}

static id Send(CBLManager* server, NSString* method, NSString* path,
               int expectedStatus, id expectedResult) {
    return SendBody(server, method, path, nil, expectedStatus, expectedResult);
}

static void CheckCacheable(CBLManager* server, NSString* path) {
    NSString* eTag = (sLastResponse.headers)[@"Etag"];
    CAssert(eTag.length > 0, @"Missing eTag in response for %@", path);
    sLastResponse = SendRequest(server, @"GET", path, $dict({@"If-None-Match", eTag}), nil);
    CAssertEq(sLastResponse.status, kCBLStatusNotModified);
}


#pragma mark - BASICS


TestCase(CBL_Router_Server) {
    RequireTestCase(CBLManager);
    CBLManager* server = createDBManager();
    Send(server, @"GET", @"/", kCBLStatusOK, $dict({@"CouchbaseLite", @"Welcome"},
                                          {@"couchdb", @"Welcome"},
                                          {@"version", CBLVersionString()}));
    Send(server, @"GET", @"/_all_dbs", kCBLStatusOK, @[]);
    Send(server, @"GET", @"/non-existent", kCBLStatusNotFound, nil);
    Send(server, @"GET", @"/BadName", kCBLStatusBadID, nil);
    Send(server, @"PUT", @"/", kCBLStatusBadRequest, nil);
    NSDictionary* response = Send(server, @"POST", @"/", kCBLStatusBadRequest, nil);
    
    CAssertEqual(response[@"status"], @(400));
    CAssertEqual(response[@"error"], @"bad_request");
    
    NSDictionary* session = Send(server, @"GET", @"/_session", kCBLStatusOK, nil);
    CAssert(session[@"ok"]);

    // Send a Persona assertion to the server, should get back an email address.
    // This is an assertion generated by persona.org on 1/13/2013.
    NSString* sampleAssertion = @"eyJhbGciOiJSUzI1NiJ9.eyJwdWJsaWMta2V5Ijp7ImFsZ29yaXRobSI6IkRTIiwieSI6ImNhNWJiYTYzZmI4MDQ2OGE0MjFjZjgxYTIzN2VlMDcwYTJlOTM4NTY0ODhiYTYzNTM0ZTU4NzJjZjllMGUwMDk0ZWQ2NDBlOGNhYmEwMjNkYjc5ODU3YjkxMzBlZGNmZGZiNmJiNTUwMWNjNTk3MTI1Y2NiMWQ1ZWQzOTVjZTMyNThlYjEwN2FjZTM1ODRiOWIwN2I4MWU5MDQ4NzhhYzBhMjFlOWZkYmRjYzNhNzNjOTg3MDAwYjk4YWUwMmZmMDQ4ODFiZDNiOTBmNzllYzVlNDU1YzliZjM3NzFkYjEzMTcxYjNkMTA2ZjM1ZDQyZmZmZjQ2ZWZiZDcwNjgyNWQiLCJwIjoiZmY2MDA0ODNkYjZhYmZjNWI0NWVhYjc4NTk0YjM1MzNkNTUwZDlmMWJmMmE5OTJhN2E4ZGFhNmRjMzRmODA0NWFkNGU2ZTBjNDI5ZDMzNGVlZWFhZWZkN2UyM2Q0ODEwYmUwMGU0Y2MxNDkyY2JhMzI1YmE4MWZmMmQ1YTViMzA1YThkMTdlYjNiZjRhMDZhMzQ5ZDM5MmUwMGQzMjk3NDRhNTE3OTM4MDM0NGU4MmExOGM0NzkzMzQzOGY4OTFlMjJhZWVmODEyZDY5YzhmNzVlMzI2Y2I3MGVhMDAwYzNmNzc2ZGZkYmQ2MDQ2MzhjMmVmNzE3ZmMyNmQwMmUxNyIsInEiOiJlMjFlMDRmOTExZDFlZDc5OTEwMDhlY2FhYjNiZjc3NTk4NDMwOWMzIiwiZyI6ImM1MmE0YTBmZjNiN2U2MWZkZjE4NjdjZTg0MTM4MzY5YTYxNTRmNGFmYTkyOTY2ZTNjODI3ZTI1Y2ZhNmNmNTA4YjkwZTVkZTQxOWUxMzM3ZTA3YTJlOWUyYTNjZDVkZWE3MDRkMTc1ZjhlYmY2YWYzOTdkNjllMTEwYjk2YWZiMTdjN2EwMzI1OTMyOWU0ODI5YjBkMDNiYmM3ODk2YjE1YjRhZGU1M2UxMzA4NThjYzM0ZDk2MjY5YWE4OTA0MWY0MDkxMzZjNzI0MmEzODg5NWM5ZDViY2NhZDRmMzg5YWYxZDdhNGJkMTM5OGJkMDcyZGZmYTg5NjIzMzM5N2EifSwicHJpbmNpcGFsIjp7ImVtYWlsIjoiamVuc0Btb29zZXlhcmQuY29tIn0sImlhdCI6MTM1ODI5NjIzNzU3NywiZXhwIjoxMzU4MzgyNjM3NTc3LCJpc3MiOiJsb2dpbi5wZXJzb25hLm9yZyJ9.RnDK118nqL2wzpLCVRzw1MI4IThgeWpul9jPl6ypyyxRMMTurlJbjFfs-BXoPaOem878G8-4D2eGWS6wd307k7xlPysevYPogfFWxK_eDHwkTq3Ts91qEDqrdV_JtgULC8c1LvX65E0TwW_GL_TM94g3CvqoQnGVxxoaMVye4ggvR7eOZjimWMzUuu4Lo9Z-VBHBj7XM0UMBie57CpGwH4_Wkv0V_LHZRRHKdnl9ISp_aGwfBObTcHG9v0P3BW9vRrCjihIn0SqOJQ9obl52rMf84GD4Lcy9NIktzfyka70xR9Sh7ALotW7rWywsTzMTu3t8AzMz2MJgGjvQmx49QA~eyJhbGciOiJEUzEyOCJ9.eyJleHAiOjEzNTgyOTY0Mzg0OTUsImF1ZCI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDk4NC8ifQ.4FV2TrUQffDya0MOxOQlzJQbDNvCPF2sfTIJN7KOLvvlSFPknuIo5g";

    NSDictionary* asserted = SendBody(server, @"POST", @"/_persona_assertion", $dict({@"assertion", sampleAssertion}), kCBLStatusOK, nil);
    CAssert(asserted[@"ok"]);
    CAssertEqual(asserted[@"email"], @"jens@mooseyard.com");

    [server close];
}


TestCase(CBL_Router_Databases) {
    RequireTestCase(CBL_Router_Server);
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/database", kCBLStatusCreated, nil);
    
    NSDictionary* dbInfo = Send(server, @"GET", @"/database", kCBLStatusOK, nil);
    CAssertEq([dbInfo[@"doc_count"] intValue], 0);
    CAssertEq([dbInfo[@"update_seq"] intValue], 0);
    CAssert([dbInfo[@"disk_size"] intValue] > 8000);
    
    Send(server, @"PUT", @"/database", kCBLStatusDuplicate, nil);
    Send(server, @"PUT", @"/database2", kCBLStatusCreated, nil);
    Send(server, @"GET", @"/_all_dbs", kCBLStatusOK, @[@"database", @"database2"]);
    dbInfo = Send(server, @"GET", @"/database2", kCBLStatusOK, nil);
    CAssertEqual(dbInfo[@"db_name"], @"database2");
    Send(server, @"DELETE", @"/database2", kCBLStatusOK, nil);
    Send(server, @"GET", @"/_all_dbs", kCBLStatusOK, @[@"database"]);

    Send(server, @"PUT", @"/database%2Fwith%2Fslashes", kCBLStatusCreated, nil);
    dbInfo = Send(server, @"GET", @"/database%2Fwith%2Fslashes", kCBLStatusOK, nil);
    CAssertEqual(dbInfo[@"db_name"], @"database/with/slashes");
    [server close];
}


// Subroutine used by CBL_Router_Docs, etc.
static NSArray* populateDocs(CBLManager* server) {
    // PUT:
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    CAssert([revID hasPrefix: @"1-"]);

    // PUT to update:
    result = SendBody(server, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID}), 
                      kCBLStatusCreated, nil);
    Log(@"PUT returned %@", result);
    revID = result[@"rev"];
    CAssert([revID hasPrefix: @"2-"]);
    
    Send(server, @"GET", @"/db/doc1", kCBLStatusOK,
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"goodbye"}));
    CheckCacheable(server, @"/db/doc1");
    
    // Add more docs:
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];

    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", kCBLStatusOK, nil);
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
    result = Send(server, @"DELETE", $sprintf(@"/db/doc1?rev=%@", revID), kCBLStatusOK, nil);
    revID = result[@"rev"];
    CAssert([revID hasPrefix: @"3-"]);

    Send(server, @"GET", @"/db/doc1", kCBLStatusDeleted, nil);
    return @[revID, revID2, revID3];
}


TestCase(CBL_Router_Docs) {
    RequireTestCase(CBL_Router_Databases);
    CBLManager* server = createDBManager();
    populateDocs(server);
    [server close];
}


TestCase(CBL_Router_LocalDocs) {
    RequireTestCase(CBL_Database_LocalDocs);
    RequireTestCase(CBL_Router_Docs);
    // PUT a local doc:
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/_local/doc1", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    CAssert([revID hasPrefix: @"1-"]);
    
    // GET it:
    Send(server, @"GET", @"/db/_local/doc1", kCBLStatusOK,
         $dict({@"_id", @"_local/doc1"},
               {@"_rev", revID},
               {@"message", @"hello"}));
    CheckCacheable(server, @"/db/_local/doc1");

    // Local doc should not appear in _changes feed:
    Send(server, @"GET", @"/db/_changes", kCBLStatusOK,
         $dict({@"last_seq", @0},
               {@"results", @[]}));
    [server close];
}


TestCase(CBL_Router_AllDocs) {
    // PUT:
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    
    NSDictionary* result;
    result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kCBLStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", kCBLStatusOK, nil);
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
    result = Send(server, @"GET", @"/db/_all_docs?include_docs=true", kCBLStatusOK, nil);
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


TestCase(CBL_Router_Views) {
    // PUT:
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    
    SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);
    SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kCBLStatusCreated, nil);
    SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);
    
    CBLDatabase* db = [server existingDatabaseNamed: @"db" error: NULL];
    CBLView* view = [db viewNamed: @"design/view"];
    [view setMapBlock:  MAPBLOCK({
        if (doc[@"message"])
            emit(doc[@"message"], nil);
    }) reduceBlock: NULL version: @"1"];

    // Query the view and check the result:
    Send(server, @"GET", @"/db/_design/design/_view/view", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}),
                                $dict({@"id", @"doc2"}, {@"key", @"guten tag"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @3}));
    
    // Check the ETag:
    CBLResponse* response = SendRequest(server, @"GET", @"/db/_design/design/_view/view", nil, nil);
    NSString* etag = (response.headers)[@"Etag"];
    CAssertEqual(etag, $sprintf(@"\"%lld\"", view.lastSequenceIndexed));
    
    // Try a conditional GET:
    response = SendRequest(server, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    CAssertEq(response.status, kCBLStatusNotModified);

    // Update the database:
    SendBody(server, @"PUT", @"/db/doc4", $dict({@"message", @"aloha"}), kCBLStatusCreated, nil);
    
    // Try a conditional GET:
    response = SendRequest(server, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    CAssertEq(response.status, kCBLStatusOK);
    CAssertEqual(ParseJSONResponse(response)[@"total_rows"], @4);

    // Query the view with "?key="
    Send(server, @"GET", @"/db/_design/design/_view/view?key=%22bonjour%22", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}) )},
               {@"total_rows", @1}));

    // Query the view with "?keys="
    Send(server, @"GET", @"/db/_design/design/_view/view?keys=%5B%22bonjour%22,%22hello%22%5D",
         kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @2}));
    
    [server close];
}


#pragma mark - CHANGES:


TestCase(CBL_Router_Changes) {
    RequireTestCase(CBL_Router_Docs);
    CBLManager* server = createDBManager();
    NSArray* revIDs = populateDocs(server);

    // _changes:
    Send(server, @"GET", @"/db/_changes", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc3"},
                                         {@"changes", $array($dict({@"rev", revIDs[2]}))},
                                         {@"seq", @3}),
                                   $dict({@"id", @"doc2"},
                                         {@"changes", $array($dict({@"rev", revIDs[1]}))},
                                         {@"seq", @4}),
                                   $dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                         {@"seq", @5},
                                         {@"deleted", $true}))}));
    CheckCacheable(server, @"/db/_changes");

    // _changes with ?since:
    Send(server, @"GET", @"/db/_changes?since=4", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                         {@"seq", @5},
                                         {@"deleted", $true}))}));
    Send(server, @"GET", @"/db/_changes?since=5", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", @[]}));
    [server close];
}


TestCase(CBL_Router_LongPollChanges) {
    RequireTestCase(CBL_Router_Changes);
    CBLManager* server = createDBManager();
    populateDocs(server);

    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;

    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=longpoll&since=5"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: server request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
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
    CAssert(!finished);

    // Now make a change to the database:
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc4",
                                    $dict({@"message", @"hej"}), kCBLStatusCreated, nil);
    NSString* revID6 = result[@"rev"];

    // Should now have received a response from the router with one revision:
    CAssert(finished);
    NSDictionary* changes = [CBLJSON JSONObjectWithData: body options: 0 error: NULL];
    CAssert(changes, @"Couldn't parse response body:\n%@", body.my_UTF8ToString);
    CAssertEqual(changes, $dict({@"last_seq", @6},
                                {@"results", $array($dict({@"id", @"doc4"},
                                                          {@"changes", $array($dict({@"rev", revID6}))},
                                                          {@"seq", @6}))}));
    [router stop];
    [server close];
}


TestCase(CBL_Router_ContinuousChanges) {
    RequireTestCase(CBL_Router_Changes);
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);

    SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);

    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=continuous"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: server request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
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
    CAssertEq(response.status, kCBLStatusOK);
    CAssert(body.length > 0);
    CAssert(!finished);
    [body setLength: 0];
    
    // Now make a change to the database:
    SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hej"}), kCBLStatusCreated, nil);

    // Should now have received additional output from the router:
    CAssert(body.length > 0);
    CAssert(!finished);
    
    [router stop];
    [server close];
}


#pragma mark - ATTACHMENTS:


static NSDictionary* createDocWithAttachments(CBLManager* server,
                                              NSData* attach1, NSData* attach2) {
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    NSString* base64 = [CBLBase64 encode: attach1];
    NSString* base642 = [CBLBase64 encode: attach2];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})},
                                         {@"path/to/attachment",
                                                     $dict({@"content_type", @"text/plain"},
                                                           {@"data", base642})});
    NSDictionary* props = $dict({@"message", @"hello"},
                                {@"_attachments", attachmentDict});

    return SendBody(server, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
}


TestCase(CBL_Router_GetAttachment) {
    CBLManager* server = createDBManager();

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* result = createDocWithAttachments(server, attach1, attach2);
    NSString* revID = result[@"rev"];

    // Now get the attachment via its URL:
    CBLResponse* response = SendRequest(server, @"GET", @"/db/doc1/attach", nil, nil);
    CAssertEq(response.status, kCBLStatusOK);
    CAssertEqual(response.body.asJSON, attach1);
    CAssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    NSString* eTag = (response.headers)[@"Etag"];
    CAssert(eTag.length > 0);
    
    // Ditto the 2nd attachment, whose name contains "/"s:
    response = SendRequest(server, @"GET", @"/db/doc1/path/to/attachment", nil, nil);
    CAssertEq(response.status, kCBLStatusOK);
    CAssertEqual(response.body.asJSON, attach2);
    CAssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    eTag = (response.headers)[@"Etag"];
    CAssert(eTag.length > 0);
    
    // A nonexistent attachment should result in a kCBLStatusNotFound:
    response = SendRequest(server, @"GET", @"/db/doc1/bogus", nil, nil);
    CAssertEq(response.status, kCBLStatusNotFound);
    
    response = SendRequest(server, @"GET", @"/db/missingdoc/bogus", nil, nil);
    CAssertEq(response.status, kCBLStatusNotFound);
    
    // Get the document with attachment data:
    response = SendRequest(server, @"GET", @"/db/doc1?attachments=true", nil, nil);
    CAssertEq(response.status, kCBLStatusOK);
    CAssertEqual((response.body)[@"_attachments"],
                 $dict({@"attach", $dict({@"data", [CBLBase64 encode: attach1]}, 
                                        {@"content_type", @"text/plain"},
                                        {@"length", @(attach1.length)},
                                        {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                         {@"revpos", @1})},
                       {@"path/to/attachment", $dict({@"data", [CBLBase64 encode: attach2]}, 
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
    result = SendBody(server, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
    revID = result[@"rev"];
    
    // Get the doc with attachments modified since rev #1:
    NSString* path = $sprintf(@"/db/doc1?attachments=true&atts_since=[%%22%@%%22]", revID);
    Send(server, @"GET", path, kCBLStatusOK, 
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


TestCase(CBL_Router_GetRange) {
    CBLManager* server = createDBManager();

    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    createDocWithAttachments(server, attach1, attach2);

    CBLResponse* response = SendRequest(server, @"GET", @"/db/doc1/attach",
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
    [server close];
}


TestCase(CBL_Router_PutMultipart) {
    RequireTestCase(CBL_Router_Docs);
    RequireTestCase(CBLMultipartDownloader);
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    
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
                              [CBLJSON stringWithJSONObject: props options: 0 error: NULL],
                              attachmentString);
    
    CBLResponse* response = SendRequest(server, @"PUT", @"/db/doc",
                           $dict({@"Content-Type", @"multipart/related; boundary=\"BOUNDARY\""}),
                                       [body dataUsingEncoding: NSUTF8StringEncoding]);
    CAssertEq(response.status, kCBLStatusCreated);
    [server close];
}


#pragma mark - REVS:


TestCase(CBL_Router_OpenRevs) {
    RequireTestCase(CBL_Router_Databases);
    // PUT:
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID1 = result[@"rev"];
    
    // PUT to update:
    result = SendBody(server, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID1}), 
                      kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    Send(server, @"GET", @"/db/doc1?open_revs=all", kCBLStatusOK,
         $array( $dict({@"ok", $dict({@"_id", @"doc1"},
                                     {@"_rev", revID2},
                                     {@"message", @"goodbye"})}) ));
    Send(server, @"GET", $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, revID2), kCBLStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID2},
                                    {@"message", @"goodbye"})})
                ));
    Send(server, @"GET", $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, @"bogus"), kCBLStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"missing", @"bogus"})
                ));
    [server close];
}


TestCase(CBL_Router_RevsDiff) {
    RequireTestCase(CBL_Router_Databases);
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    NSDictionary* doc1r1 = SendBody(server, @"PUT", @"/db/11111", $dict(), kCBLStatusCreated,nil);
    NSString* doc1r1ID = doc1r1[@"rev"];
    NSDictionary* doc2r1 = SendBody(server, @"PUT", @"/db/22222", $dict(), kCBLStatusCreated,nil);
    NSString* doc2r1ID = doc2r1[@"rev"];
    NSDictionary* doc3r1 = SendBody(server, @"PUT", @"/db/33333", $dict(), kCBLStatusCreated,nil);
    NSString* doc3r1ID = doc3r1[@"rev"];
    
    NSDictionary* doc1r2 = SendBody(server, @"PUT", @"/db/11111", $dict({@"_rev", doc1r1ID}), kCBLStatusCreated,nil);
    NSString* doc1r2ID = doc1r2[@"rev"];
    SendBody(server, @"PUT", @"/db/22222", $dict({@"_rev", doc2r1ID}), kCBLStatusCreated,nil);

    NSDictionary* doc1r3 = SendBody(server, @"PUT", @"/db/11111", $dict({@"_rev", doc1r2ID}), kCBLStatusCreated,nil);
    NSString* doc1r3ID = doc1r3[@"rev"];
    
    SendBody(server, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"3-foo"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-bar"]},
                   {@"99999", @[@"6-six"]}),
             kCBLStatusOK,
             $dict({@"11111", $dict({@"missing", @[@"3-foo"]},
                                    {@"possible_ancestors", @[doc1r2ID, doc1r1ID]})},
                   {@"33333", $dict({@"missing", @[@"10-bar"]},
                                    {@"possible_ancestors", @[doc3r1ID]})},
                   {@"99999", $dict({@"missing", @[@"6-six"]})}
                   ));
    
    // Compact the database -- this will null out the JSON of doc1r1 & doc1r2,
    // and they won't be returned as possible ancestors anymore.
    Send(server, @"POST", @"/db/_compact", kCBLStatusAccepted, nil);
    
    SendBody(server, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"4-foo"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-bar"]},
                   {@"99999", @[@"6-six"]}),
             kCBLStatusOK,
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


TestCase(CBL_Router_AccessCheck) {
    RequireTestCase(CBL_Router_Databases);
    CBLManager* server = createDBManager();
    Send(server, @"PUT", @"/db", kCBLStatusCreated, nil);
    
    NSURL* url = [NSURL URLWithString: @"cbl:///db/"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = @"GET";
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: server request: request];
    CAssert(router!=nil);
    __block BOOL calledOnAccessCheck = NO;
    router.onAccessCheck = ^CBLStatus(CBLDatabase* accessDB, NSString* docID, SEL action) {
        CAssert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 200;
    };
    [router start];
    CAssert(calledOnAccessCheck);
    CAssert(router.response.status == 200);
    
    router = [[CBL_Router alloc] initWithDatabaseManager: server request: request];
    CAssert(router!=nil);
    calledOnAccessCheck = NO;
    router.onAccessCheck = ^CBLStatus(CBLDatabase* accessDB, NSString* docID, SEL action) {
        CAssert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 401;
    };
    [router start];
    
    CAssert(calledOnAccessCheck);
    CAssert(router.response.status == 401);
    [server close];
}


TestCase(CBL_Router) {
    RequireTestCase(CBL_Router_Server);
    RequireTestCase(CBL_Router_Databases);
    RequireTestCase(CBL_Router_Docs);
    RequireTestCase(CBL_Router_AllDocs);
    RequireTestCase(CBL_Router_LongPollChanges);
    RequireTestCase(CBL_Router_ContinuousChanges);
    RequireTestCase(CBL_Router_GetAttachment);
    RequireTestCase(CBL_Router_RevsDiff);
    RequireTestCase(CBL_Router_AccessCheck);
}

#endif
