//
//  Router_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/23/14.
//
//

#import "CBLTestCase.h"
#import "CBL_Router.h"
#import "CBLDatabase.h"
#import "CBL_Body.h"
#import "CBL_Server.h"
#import "CBLJSViewCompiler.h"
#import "CBLBase64.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CBL_URLProtocol.h"


@interface CBL_Router ()
- (instancetype) initWithDatabaseManager: (CBLManager*)dbManager request: (NSURLRequest*)request;
- (void) stopNow;
@end


@interface Router_Tests : CBLTestCaseWithDB
@end


@implementation Router_Tests
{
    NSTimeInterval _savedMinHeartbeat;
}


static CBLResponse* SendRequest(Router_Tests* self, NSString* method, NSString* path,
                                NSDictionary* headers, id bodyObj) {
    NSURL* url = [NSURL URLWithString: [@"cbl://" stringByAppendingString: path]];
    Assert(url, @"Invalid URL: <%@>", path);
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
            AssertNil(error);
        }
    }
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: self->dbmgr request: request];
    Assert(router!=nil);
    __block CBLResponse* response = nil;
    __block NSUInteger dataLength = 0;
    __block BOOL calledOnFinished = NO;
    router.onResponseReady = ^(CBLResponse* theResponse) {Assert(!response); response = theResponse;};
    router.onDataAvailable = ^(NSData* data, BOOL finished) {dataLength += data.length;};
    router.onFinished = ^{Assert(!calledOnFinished); calledOnFinished = YES;};
    [router start];
    Assert(response);
    AssertEq(dataLength, response.body.asJSON.length);
    Assert(calledOnFinished);
    Log(@"%@ %@ --> %d", method, path, response.status);
    return response;
}

static id ParseJSONResponse(Router_Tests* self, CBLResponse* response) {
    NSData* json = response.body.asJSON;
    NSString* jsonStr = nil;
    id result = nil;
    if (json) {
        jsonStr = [[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding];
        Assert(jsonStr);
        NSError* error;
        result = [CBLJSON JSONObjectWithData: json options: 0 error: &error];
        Assert(result, @"Couldn't parse JSON response: %@", error);
    }
    return result;
}

static CBLResponse* sLastResponse;

static id SendBody(Router_Tests* self, NSString* method, NSString* path, id bodyObj,
                   CBLStatus expectedStatus, id expectedResult) {
    sLastResponse = SendRequest(self, method, path, @{@"Accept": @"application/json"}, bodyObj);
    id result = ParseJSONResponse(self, sLastResponse);
    Assert(result != nil);

    AssertEq(sLastResponse.internalStatus, expectedStatus);

    if (expectedResult)
        AssertEqual(result, expectedResult);
    return result;
}

static id Send(Router_Tests* self, NSString* method, NSString* path,
               int expectedStatus, id expectedResult) {
    return SendBody(self, method, path, nil, expectedStatus, expectedResult);
}

static void CheckCacheable(Router_Tests* self, NSString* path) {
    NSString* eTag = (sLastResponse.headers)[@"Etag"];
    Assert(eTag.length > 0, @"Missing eTag in response for %@", path);
    sLastResponse = SendRequest(self, @"GET", path, $dict({@"If-None-Match", eTag}), nil);
    AssertEq(sLastResponse.status, kCBLStatusNotModified);
}


#pragma mark - BASICS


- (void) setUp {
    [super setUp];
    // Disable minimum heartbeat so that we can test it with short values to make the test quicker
    _savedMinHeartbeat = kMinHeartbeat;
    kMinHeartbeat = 0.0;
}

- (void) tearDown {
    kMinHeartbeat = _savedMinHeartbeat;
    [super tearDown];
}


- (void) test_Server {
    RequireTestCase(CBLManager);
    Send(self, @"GET", @"/", kCBLStatusOK, $dict({@"CouchbaseLite", @"Welcome"},
                                                   {@"couchdb", @"Welcome"},
                                                   {@"version", CBLVersion()},
                                                   {@"vendor", @{@"name": @"Couchbase Lite (Objective-C)",
                                                                 @"version": CBLVersion()}}));
    Send(self, @"GET", @"/_all_dbs", kCBLStatusOK, @[db.name]);
    Send(self, @"GET", @"/non-existent", kCBLStatusNotFound, nil);
    Send(self, @"GET", @"/BadName", kCBLStatusBadID, nil);
    Send(self, @"PUT", @"/", kCBLStatusMethodNotAllowed, nil);
    NSDictionary* response = Send(self, @"POST", @"/", kCBLStatusMethodNotAllowed, nil);
    
    AssertEqual(response[@"status"], @(405));
    AssertEqual(response[@"error"], @"method_not_allowed");
    
    NSDictionary* session = Send(self, @"GET", @"/_session", kCBLStatusOK, nil);
    Assert(session[@"ok"]);

    // Send a Persona assertion to the server, should get back an email address.
    // This is an assertion generated by persona.org on 1/13/2013.
    NSString* sampleAssertion = @"eyJhbGciOiJSUzI1NiJ9.eyJwdWJsaWMta2V5Ijp7ImFsZ29yaXRobSI6IkRTIiwieSI6ImNhNWJiYTYzZmI4MDQ2OGE0MjFjZjgxYTIzN2VlMDcwYTJlOTM4NTY0ODhiYTYzNTM0ZTU4NzJjZjllMGUwMDk0ZWQ2NDBlOGNhYmEwMjNkYjc5ODU3YjkxMzBlZGNmZGZiNmJiNTUwMWNjNTk3MTI1Y2NiMWQ1ZWQzOTVjZTMyNThlYjEwN2FjZTM1ODRiOWIwN2I4MWU5MDQ4NzhhYzBhMjFlOWZkYmRjYzNhNzNjOTg3MDAwYjk4YWUwMmZmMDQ4ODFiZDNiOTBmNzllYzVlNDU1YzliZjM3NzFkYjEzMTcxYjNkMTA2ZjM1ZDQyZmZmZjQ2ZWZiZDcwNjgyNWQiLCJwIjoiZmY2MDA0ODNkYjZhYmZjNWI0NWVhYjc4NTk0YjM1MzNkNTUwZDlmMWJmMmE5OTJhN2E4ZGFhNmRjMzRmODA0NWFkNGU2ZTBjNDI5ZDMzNGVlZWFhZWZkN2UyM2Q0ODEwYmUwMGU0Y2MxNDkyY2JhMzI1YmE4MWZmMmQ1YTViMzA1YThkMTdlYjNiZjRhMDZhMzQ5ZDM5MmUwMGQzMjk3NDRhNTE3OTM4MDM0NGU4MmExOGM0NzkzMzQzOGY4OTFlMjJhZWVmODEyZDY5YzhmNzVlMzI2Y2I3MGVhMDAwYzNmNzc2ZGZkYmQ2MDQ2MzhjMmVmNzE3ZmMyNmQwMmUxNyIsInEiOiJlMjFlMDRmOTExZDFlZDc5OTEwMDhlY2FhYjNiZjc3NTk4NDMwOWMzIiwiZyI6ImM1MmE0YTBmZjNiN2U2MWZkZjE4NjdjZTg0MTM4MzY5YTYxNTRmNGFmYTkyOTY2ZTNjODI3ZTI1Y2ZhNmNmNTA4YjkwZTVkZTQxOWUxMzM3ZTA3YTJlOWUyYTNjZDVkZWE3MDRkMTc1ZjhlYmY2YWYzOTdkNjllMTEwYjk2YWZiMTdjN2EwMzI1OTMyOWU0ODI5YjBkMDNiYmM3ODk2YjE1YjRhZGU1M2UxMzA4NThjYzM0ZDk2MjY5YWE4OTA0MWY0MDkxMzZjNzI0MmEzODg5NWM5ZDViY2NhZDRmMzg5YWYxZDdhNGJkMTM5OGJkMDcyZGZmYTg5NjIzMzM5N2EifSwicHJpbmNpcGFsIjp7ImVtYWlsIjoiamVuc0Btb29zZXlhcmQuY29tIn0sImlhdCI6MTM1ODI5NjIzNzU3NywiZXhwIjoxMzU4MzgyNjM3NTc3LCJpc3MiOiJsb2dpbi5wZXJzb25hLm9yZyJ9.RnDK118nqL2wzpLCVRzw1MI4IThgeWpul9jPl6ypyyxRMMTurlJbjFfs-BXoPaOem878G8-4D2eGWS6wd307k7xlPysevYPogfFWxK_eDHwkTq3Ts91qEDqrdV_JtgULC8c1LvX65E0TwW_GL_TM94g3CvqoQnGVxxoaMVye4ggvR7eOZjimWMzUuu4Lo9Z-VBHBj7XM0UMBie57CpGwH4_Wkv0V_LHZRRHKdnl9ISp_aGwfBObTcHG9v0P3BW9vRrCjihIn0SqOJQ9obl52rMf84GD4Lcy9NIktzfyka70xR9Sh7ALotW7rWywsTzMTu3t8AzMz2MJgGjvQmx49QA~eyJhbGciOiJEUzEyOCJ9.eyJleHAiOjEzNTgyOTY0Mzg0OTUsImF1ZCI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDk4NC8ifQ.4FV2TrUQffDya0MOxOQlzJQbDNvCPF2sfTIJN7KOLvvlSFPknuIo5g";

    NSDictionary* asserted = SendBody(self, @"POST", @"/_persona_assertion", $dict({@"assertion", sampleAssertion}), kCBLStatusOK, nil);
    Assert(asserted[@"ok"]);
    AssertEqual(asserted[@"email"], @"jens@mooseyard.com");
}


- (void) test_Databases {
    RequireTestCase(Server);
    Send(self, @"PUT", @"/database", kCBLStatusCreated, nil);
    
    NSDictionary* dbInfo = Send(self, @"GET", @"/database", kCBLStatusOK, nil);
    AssertEq([dbInfo[@"doc_count"] intValue], 0);
    AssertEq([dbInfo[@"update_seq"] intValue], 0);
    Assert([dbInfo[@"disk_size"] intValue] > 8000);
    
    Send(self, @"PUT", @"/database", kCBLStatusDuplicate, nil);
    Send(self, @"PUT", @"/database2", kCBLStatusCreated, nil);
    Send(self, @"GET", @"/_all_dbs", kCBLStatusOK, @[@"database", @"database2", db.name]);
    dbInfo = Send(self, @"GET", @"/database2", kCBLStatusOK, nil);
    AssertEqual(dbInfo[@"db_name"], @"database2");
    Send(self, @"DELETE", @"/database2", kCBLStatusOK, nil);
    Send(self, @"GET", @"/_all_dbs", kCBLStatusOK, @[@"database", db.name]);

    Send(self, @"PUT", @"/database%2Fwith%2Fslashes", kCBLStatusCreated, nil);
    dbInfo = Send(self, @"GET", @"/database%2Fwith%2Fslashes", kCBLStatusOK, nil);
    AssertEqual(dbInfo[@"db_name"], @"database/with/slashes");
}


// Subroutine used by CBL_Router_Docs, etc.
- (NSArray*) populateDocs {
    // PUT:
    NSDictionary* result = SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}),
                                    kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    Assert([revID hasPrefix: @"1-"]);

    // PUT to update:
    result = SendBody(self, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID}), 
                      kCBLStatusCreated, nil);
    Log(@"PUT returned %@", result);
    revID = result[@"rev"];
    Assert([revID hasPrefix: @"2-"]);

    // Add more docs:
    result = SendBody(self, @"PUT", @"/db/doc3", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"hello"}), 
                                    kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];

    // _all_docs:
    result = Send(self, @"GET", @"/db/_all_docs", kCBLStatusOK, nil);
    AssertEqual(result[@"total_rows"], @3);
    AssertEqual(result[@"offset"], @0);
    NSArray* rows = result[@"rows"];
    AssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));
    CheckCacheable(self, @"/db/_all_docs");

    // DELETE:
    result = Send(self, @"DELETE", $sprintf(@"/db/doc1?rev=%@", revID), kCBLStatusOK, nil);
    revID = result[@"rev"];
    Assert([revID hasPrefix: @"3-"]);

    Send(self, @"GET", @"/db/doc1", kCBLStatusDeleted, nil);
    return @[revID, revID2, revID3];
}


- (void) test_Docs {
    RequireTestCase(Databases);
    NSArray* revIDs = [self populateDocs];

    Send(self, @"GET", @"/db/doc2", kCBLStatusOK,
         $dict({@"_id", @"doc2"}, {@"_rev", revIDs[1]}, {@"message", @"hello"}));
    CheckCacheable(self, @"/db/doc2");

    Send(self, @"GET", @"/db/doc2?revs=true", kCBLStatusOK,
         @{@"_id": @"doc2",
           @"_rev": revIDs[1],
           @"_revisions": @{@"ids": @[[revIDs[1] substringFromIndex: 2]], @"start": @1},
           @"message": @"hello"});

    Send(self, @"GET", @"/db/doc2?revs_info=true", kCBLStatusOK,
         @{@"_id": @"doc2",
           @"_rev": revIDs[1],
           @"_revs_info": @[@{@"rev": revIDs[1], @"status": @"available"}],
           @"message": @"hello"});

    Send(self, @"GET", @"/db/doc2?conflicts=true", kCBLStatusOK,
         @{@"_id": @"doc2",
           @"_rev": revIDs[1],
           @"message": @"hello"});
}


- (void) test_LocalDocs {
    RequireTestCase(CBL_Database_LocalDocs);
    RequireTestCase(Docs);
    // PUT a local doc:
    NSDictionary* result = SendBody(self, @"PUT", @"/db/_local/doc1", $dict({@"message", @"hello"}),
                                    kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    Assert([revID hasPrefix: @"1-"]);
    
    // GET it:
    Send(self, @"GET", @"/db/_local/doc1", kCBLStatusOK,
         $dict({@"_id", @"_local/doc1"},
               {@"_rev", revID},
               {@"message", @"hello"}));
    CheckCacheable(self, @"/db/_local/doc1");

    // Local doc should not appear in _changes feed:
    Send(self, @"GET", @"/db/_changes", kCBLStatusOK,
         $dict({@"last_seq", @0},
               {@"results", @[]}));
}


- (void) test_AllDocs {
    // PUT:
    NSDictionary* result;
    result = SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);
    NSString* revID = result[@"rev"];
    result = SendBody(self, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kCBLStatusCreated, nil);
    NSString* revID3 = result[@"rev"];
    result = SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    // _all_docs:
    result = Send(self, @"GET", @"/db/_all_docs", kCBLStatusOK, nil);
    AssertEqual(result[@"total_rows"], @3);
    AssertEqual(result[@"offset"], @0);
    NSArray* rows = result[@"rows"];
    AssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));
    
    // ?include_docs:
    result = Send(self, @"GET", @"/db/_all_docs?include_docs=true", kCBLStatusOK, nil);
    AssertEqual(result[@"total_rows"], @3);
    AssertEqual(result[@"offset"], @0);
    rows = result[@"rows"];
    AssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
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

    // keys:
    result = SendBody(self, @"POST", @"/db/_all_docs",
                      $dict({@"keys", $array(@"doc1", @"doc2", @"doc3", @"doc4")}),
                      kCBLStatusOK, nil);
    rows = result[@"rows"];
    AssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                   {@"value", $dict({@"rev", revID})}),
                             $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                   {@"value", $dict({@"rev", revID2})}),
                             $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                   {@"value", $dict({@"rev", revID3})}),
                             $dict({@"error",  @"not_found"}, {@"key", @"doc4"})
                             ));
}


- (void) test_Views {
    // PUT:
    SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);
    SendBody(self, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kCBLStatusCreated, nil);
    SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);
    
    CBLView* view = [db viewNamed: @"design/view"];
    [view setMapBlock:  MAPBLOCK({
        if (doc[@"message"])
            emit(doc[@"message"], nil);
    }) reduceBlock: NULL version: @"1"];

    // Query the view and check the result:
    Send(self, @"GET", @"/db/_design/design/_view/view", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}),
                                $dict({@"id", @"doc2"}, {@"key", @"guten tag"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @3}));
    
    // Check the ETag:
    CBLResponse* response = SendRequest(self, @"GET", @"/db/_design/design/_view/view", nil, nil);
    NSString* etag = (response.headers)[@"Etag"];
    AssertEqual(etag, ($sprintf(@"\"%lld\"", view.lastSequenceIndexed)));
    
    // Try a conditional GET:
    response = SendRequest(self, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    AssertEq(response.status, kCBLStatusNotModified);

    // Update the database:
    SendBody(self, @"PUT", @"/db/doc4", $dict({@"message", @"aloha"}), kCBLStatusCreated, nil);
    
    // Try a conditional GET:
    response = SendRequest(self, @"GET", @"/db/_design/design/_view/view",
                           $dict({@"If-None-Match", etag}), nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual(ParseJSONResponse(self, response)[@"total_rows"], @4);

    // Query the view with "?key="
    Send(self, @"GET", @"/db/_design/design/_view/view?key=%22bonjour%22", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}) )},
               {@"total_rows", @4}));

    // Query the view with "?keys="
    Send(self, @"GET", @"/db/_design/design/_view/view?keys=%5B%22bonjour%22,%22hello%22%5D",
         kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @4}));
}

- (void) test_Views_Stale {
    // PUT:
    SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);

    CBLView* view = [db viewNamed: @"design/view"];
    [view setMapBlock:  MAPBLOCK({
        if (doc[@"message"])
            emit(doc[@"message"], nil);
    }) reduceBlock: NULL version: @"1"];

    // Query the view and check the result:

    // No stale (upate_before):
    Send(self, @"GET", @"/db/_design/design/_view/view", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @1}));

    // Update database:
    SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);

    // Stale = ok:
    Send(self, @"GET", @"/db/_design/design/_view/view?stale=ok", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @1}));

    // Stale = update_after:
    SequenceNumber prevLastSeqIndexed = view.lastSequenceIndexed;
    Send(self, @"GET", @"/db/_design/design/_view/view?stale=update_after", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @1}));

    // Wait until the index is done or timeout:
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 5];
    while (prevLastSeqIndexed == view.lastSequenceIndexed && timeout.timeIntervalSinceNow > 0.0) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]]) {
            Warn(@"Runloop exiting unexpectedly!");
            break;
        }
    }

    // Check if the current last sequence indexed has been changed:
    Assert(prevLastSeqIndexed < view.lastSequenceIndexed);

    // Confirm the result with stale = ok:
    Send(self, @"GET", @"/db/_design/design/_view/view?stale=ok", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc2"}, {@"key", @"guten tag"}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}) )},
               {@"total_rows", @2}));

    // Bad stale value:
    Send(self, @"GET", @"//db/_design/design/_view/view?stale=no", kCBLStatusBadRequest, nil);
}


- (void) test_JSViews {
    [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];
    [CBLDatabase setFilterCompiler: [[CBLJSFilterCompiler alloc] init]];

    // PUT:
    SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);
    SendBody(self, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), kCBLStatusCreated, nil);
    SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), kCBLStatusCreated, nil);

    SendBody(self, @"PUT", @"/db/_design/design",
             @{@"views": @{@"view": @{@"map":
                                          @"function(doc){emit(doc.message, null);}"
                                      },
                           @"view2": @{@"map":
                                          @"function(doc){emit(doc.message.length, doc.message);}"
                                      }}},
             kCBLStatusCreated, nil);

    // Query view and check the result:
    id null = [NSNull null];
    Send(self, @"GET", @"/db/_design/design/_view/view", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc3"}, {@"key", @"bonjour"}, {@"value", null}),
                                $dict({@"id", @"doc2"}, {@"key", @"guten tag"}, {@"value", null}),
                                $dict({@"id", @"doc1"}, {@"key", @"hello"}, {@"value", null}) )},
               {@"total_rows", @3}));

    // Query view2 and check the result:
    Send(self, @"GET", @"/db/_design/design/_view/view2", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc1"}, {@"key", @5}, {@"value", @"hello"}),
                                $dict({@"id", @"doc3"}, {@"key", @7}, {@"value", @"bonjour"}),
                                $dict({@"id", @"doc2"}, {@"key", @9}, {@"value", @"guten tag"}) )},
               {@"total_rows", @3}));

    [self reopenTestDB];

    SendBody(self, @"PUT", @"/db/doc4", $dict({@"message", @"hi"}), kCBLStatusCreated, nil);

    // Query view2 again
    Send(self, @"GET", @"/db/_design/design/_view/view2", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc4"}, {@"key", @2}, {@"value", @"hi"}),
                                $dict({@"id", @"doc1"}, {@"key", @5}, {@"value", @"hello"}),
                                $dict({@"id", @"doc3"}, {@"key", @7}, {@"value", @"bonjour"}),
                                $dict({@"id", @"doc2"}, {@"key", @9}, {@"value", @"guten tag"}) )},
               {@"total_rows", @4}));

    // Check that both views were re-indexed:
    Assert(![db viewNamed: @"design/view"].stale);
    Assert(![db viewNamed: @"design/view2"].stale);

    // Try include_docs
    Send(self, @"GET", @"/db/_design/design/_view/view2?include_docs=true&limit=1", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc4"},
                                      {@"key", @2},
                                      {@"value", @"hi"},
                                      {@"doc", @{@"_id": @"doc4",
                                                 @"_rev": @"1-cfdd78e822bbcbc25c91e9deb9537c4b",
                                                 @"message": @"hi"}}
                                      ))},
               {@"total_rows", @4}));

    // Try include_docs with revs=true
    Send(self, @"GET", @"/db/_design/design/_view/view2?include_docs=true&revs=true&limit=1", kCBLStatusOK,
         $dict({@"offset", @0},
               {@"rows", $array($dict({@"id", @"doc4"},
                                      {@"key", @2},
                                      {@"value", @"hi"},
                                      {@"doc", @{@"_id": @"doc4",
                                                 @"_rev": @"1-cfdd78e822bbcbc25c91e9deb9537c4b",
                                                 @"_revisions": @{
                                                         @"start": @1,
                                                         @"ids": @[@"cfdd78e822bbcbc25c91e9deb9537c4b"]
                                                         },
                                                 @"message": @"hi"}}
                                      ))},
               {@"total_rows", @4}));

    [CBLView setCompiler: nil];
    [CBLDatabase setFilterCompiler: nil];
}


- (void) test_NoMappedSelectors {
    __unused NSDictionary* response = nil;

    response = Send(self, @"GET", @"/", kCBLStatusOK, nil);

    response = Send(self, @"POST", @"/", kCBLStatusMethodNotAllowed, nil);
    AssertEqual(response[@"status"], @(405));
    AssertEqual(response[@"error"], @"method_not_allowed");

    response = Send(self, @"PUT", @"/", kCBLStatusMethodNotAllowed, nil);
    AssertEqual(response[@"status"], @(405));
    AssertEqual(response[@"error"], @"method_not_allowed");

    response = Send(self, @"POST", @"/db/doc1", kCBLStatusMethodNotAllowed, nil);
    AssertEqual(response[@"status"], @(405));
    AssertEqual(response[@"error"], @"method_not_allowed");

    response = Send(self, @"GET", @"/db/_session", kCBLStatusNotFound, nil);
    AssertEqual(response[@"status"], @(404));
    AssertEqual(response[@"error"], @"not_found");
}


#pragma mark - CHANGES:


- (void) test_Changes {
    RequireTestCase(Docs);
    NSArray* revIDs = [self populateDocs];

    // _changes:
    Send(self, @"GET", @"/db/_changes", kCBLStatusOK,
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
    CheckCacheable(self, @"/db/_changes");

    // _changes with ?since:
    Send(self, @"GET", @"/db/_changes?since=4", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                         {@"seq", @5},
                                         {@"deleted", $true}))}));
    Send(self, @"GET", @"/db/_changes?since=5", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", @[]}));

    // _changes with include_docs:
    Send(self, @"GET", @"/db/_changes?since=4&include_docs=true", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                         {@"seq", @5},
                                         {@"deleted", $true},
                                         {@"doc", @{@"_id": @"doc1",
                                                    @"_rev": revIDs[0],
                                                    @"_deleted": @YES}}))}));
    

    // _changes with include_docs and revs=true:
    Send(self, @"GET", @"/db/_changes?since=4&include_docs=true&revs=true", kCBLStatusOK,
         $dict({@"last_seq", @5},
               {@"results", $array($dict({@"id", @"doc1"},
                                         {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                         {@"seq", @5},
                                         {@"deleted", $true},
                                         {@"doc", @{@"_id": @"doc1",
                                                    @"_rev": revIDs[0],
                                                    @"_revisions": @{
                                                            @"ids": @[@"69e1c04b38d144220169834e4a1d6b65",
                                                                      @"641a9554032af9bcb2351b2780161a4d",
                                                                      @"9c7ff8308d0c89a7f1fe0f4b683655c2"],
                                                            @"start": @3},
                                                    @"_deleted": @YES}}))}));
    
}


- (void) test_LongPollChanges {
    RequireTestCase(Changes);
    [self populateDocs];

    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;

    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=longpoll&since=5"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
        Assert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content, BOOL finished) {
        [body appendData: content];
    };
    router.onFinished = ^{
        Assert(!finished);
        finished = YES;
    };

    // Start:
    [router start];
    Assert(!finished);

    // Now make a change to the database:
    NSDictionary* result = SendBody(self, @"PUT", @"/db/doc4",
                                    $dict({@"message", @"hej"}), kCBLStatusCreated, nil);
    NSString* revID6 = result[@"rev"];

    // Should now have received a response from the router with one revision:
    Assert(finished);
    NSDictionary* changes = [CBLJSON JSONObjectWithData: body options: 0 error: NULL];
    Assert(changes, @"Couldn't parse response body:\n%@", body.my_UTF8ToString);
    AssertEqual(changes, $dict({@"last_seq", @6},
                                {@"results", $array($dict({@"id", @"doc4"},
                                                          {@"changes", $array($dict({@"rev", revID6}))},
                                                          {@"seq", @6}))}));
    [router stopNow];
}


- (void) test_LongPollChanges_Heartbeat {
    RequireTestCase(CBL_Router_ContinuousChanges);
    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    __block NSInteger heartbeat = 0;
    // Artificially short heartbeat (made possible by -setUp) to speed up the test
    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=longpoll&heartbeat=1000"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
        Assert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content, BOOL finished) {
        NSString* str = [[NSString alloc] initWithData: content encoding: NSUTF8StringEncoding];
        if ([str isEqualToString: @"\r\n"])
            heartbeat++;
        [body appendData: content];
    };
    router.onFinished = ^{
        Assert(!finished);
        finished = YES;
    };
    
    // Start:
    [router start];
    Assert(!finished);
    
    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.5];
    while ([[NSDate date] compare: timeout] == NSOrderedAscending
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
        ;
    
    // Should now have received additional output from the router:
    Assert(body.length > 0);
    Assert(heartbeat == 2);
    Assert(!finished);
    
    // Now make a change to the database:
    SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hej"}), kCBLStatusCreated, nil);
    Assert(finished);
    
    [router stopNow];
}


- (void) test_ContinuousChanges {
    RequireTestCase(Changes);
    SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), kCBLStatusCreated, nil);

    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=continuous"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
        Assert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content, BOOL finished) {
        [body appendData: content];
    };
    router.onFinished = ^{
        Assert(!finished);
        finished = YES;
    };
    
    // Start:
    [router start];
    
    // Should initially have a response and one line of output:
    Assert(response != nil);
    AssertEq(response.status, kCBLStatusOK);
    Assert(body.length > 0);
    Assert(!finished);
    [body setLength: 0];
    
    // Now make a change to the database:
    SendBody(self, @"PUT", @"/db/doc2", $dict({@"message", @"hej"}), kCBLStatusCreated, nil);

    // Should now have received additional output from the router:
    Assert(body.length > 0);
    Assert(!finished);
    
    [router stopNow];
}


- (void) test_ContinuousChanges_Heartbeat {
    RequireTestCase(CBL_Router_ContinuousChanges);

    __block CBLResponse* response = nil;
    NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    __block NSInteger heartbeat = 0;
    // Artificially short heartbeat (made possible by -setUp) to speed up the test
    NSURL* url = [NSURL URLWithString: @"cbl:///db/_changes?feed=continuous&heartbeat=1000"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    router.onResponseReady = ^(CBLResponse* routerResponse) {
        Assert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content, BOOL finished) {
        NSString *str = [[NSString alloc] initWithData: content encoding: NSUTF8StringEncoding];
        if ([str isEqualToString: @"\r\n"])
            heartbeat++;
        [body appendData: content];
    };
    router.onFinished = ^{
        Assert(!finished);
        finished = YES;
    };
    
    // Start:
    [router start];
    
    // Should initially have a response and one line of output:
    Assert(response != nil);
    AssertEq(response.status, kCBLStatusOK);
    Assert(body.length == 0);
    Assert(!finished);

    NSDate* timeout = [NSDate dateWithTimeIntervalSinceNow: 2.5];
    while ([[NSDate date] compare: timeout] == NSOrderedAscending
           && [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: timeout])
        ;
    
    // Should now have received additional output from the router:
    Assert(body.length > 0);
    Assert(heartbeat == 2);
    Assert(!finished);
    
    [router stopNow];
}


- (void) test_CBL_Router_Changes_BadHeartbeatParams {
    Send(self, @"GET", @"/db/_changes?feed=continuous&heartbeat=foo", kCBLStatusBadRequest, nil);
    Send(self, @"GET", @"/db/_changes?feed=continuous&heartbeat=-1", kCBLStatusBadRequest, nil);
    Send(self, @"GET", @"/db/_changes?feed=continuous&heartbeat=-0", kCBLStatusBadRequest, nil);
    Send(self, @"GET", @"/db/_changes?feed=longpoll&heartbeat=foo", kCBLStatusBadRequest, nil);
    Send(self, @"GET", @"/db/_changes?feed=longpoll&heartbeat=-1", kCBLStatusBadRequest, nil);
    Send(self, @"GET", @"/db/_changes?feed=longpoll&heartbeat=-0", kCBLStatusBadRequest, nil);
}


- (void) test_ChangesDescending {
    RequireTestCase(Changes);
    NSArray* revIDs = [self populateDocs];

    // _changes with descending = false
    Send(self, @"GET", @"/db/_changes?descending=false", kCBLStatusOK,
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
    if (self.isSQLiteDB ) {
        // _changes with descending = true
        Send(self, @"GET", @"/db/_changes?descending=true", kCBLStatusOK,
             $dict({@"last_seq", @3},
                   {@"results", $array($dict({@"id", @"doc1"},
                                             {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                             {@"seq", @5},
                                             {@"deleted", $true}),
                                       $dict({@"id", @"doc2"},
                                             {@"changes", $array($dict({@"rev", revIDs[1]}))},
                                             {@"seq", @4}),
                                       $dict({@"id", @"doc3"},
                                             {@"changes", $array($dict({@"rev", revIDs[2]}))},
                                             {@"seq", @3}))}));


        // _changes with descending = true and limit = 2
        Send(self, @"GET", @"/db/_changes?descending=true&limit=2", kCBLStatusOK,
             $dict({@"last_seq", @4},
                   {@"results", $array($dict({@"id", @"doc1"},
                                             {@"changes", $array($dict({@"rev", revIDs[0]}))},
                                             {@"seq", @5},
                                             {@"deleted", $true}),
                                       $dict({@"id", @"doc2"},
                                             {@"changes", $array($dict({@"rev", revIDs[1]}))},
                                             {@"seq", @4}))}));

        Send(self, @"GET", @"/db/_changes?descending=true&feed=continuous", kCBLStatusBadParam, nil);
        Send(self, @"GET", @"/db/_changes?descending=true&feed=longpoll", kCBLStatusBadParam, nil);
    } else {
        // https://github.com/couchbase/couchbase-lite-ios/issues/641
        Send(self, @"GET", @"/db/_changes?descending=true", kCBLStatusNotImplemented, nil);
        Send(self, @"GET", @"/db/_changes?descending=true&limit=2", kCBLStatusNotImplemented, nil);
        Send(self, @"GET", @"/db/_changes?descending=true&feed=continuous", kCBLStatusBadParam, nil);
        Send(self, @"GET", @"/db/_changes?descending=true&feed=longpoll", kCBLStatusBadParam, nil);
    }
}


#pragma mark - ATTACHMENTS:


- (void) test_PutAttachmentToNewDoc {
    CBLResponse* response = SendRequest(self, @"PUT", @"/db/doc1/attach.txt",
                                        @{@"Content-Type": @"text/plain"},
                                        [@"Hello there" dataUsingEncoding: NSUTF8StringEncoding]);
    AssertEq(response.status, 201);
}


- (void) test_PutAttachmentToExistingDoc {
    NSDictionary* props = $dict({@"message", @"hello"});
    NSDictionary* result = SendBody(self, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
    NSString* rev = result[@"rev"];
    Assert(rev);

    CBLResponse* response;
    response = SendRequest(self, @"PUT",
                           $sprintf(@"/db/doc1/attach.txt?rev=%@", rev),
                           @{@"Content-Type": @"text/plain"},
                           [@"Hello there" dataUsingEncoding: NSUTF8StringEncoding]);
    AssertEq(response.status, 201);
}


- (NSDictionary*) createDocWithAttachment: (NSData*)attach1 and: (NSData*) attach2 {
    NSString* base64 = [CBLBase64 encode: attach1];
    NSString* base642 = [CBLBase64 encode: attach2];
    NSDictionary* attachmentDict = $dict({@"attach", $dict({@"content_type", @"text/plain"},
                                                           {@"data", base64})},
                                         {@"path/to/attachment",
                                                     $dict({@"content_type", @"text/plain"},
                                                           {@"data", base642})});
    NSDictionary* props = $dict({@"message", @"hello"},
                                {@"_attachments", attachmentDict});

    return SendBody(self, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
}


- (void) test_GetAttachment {
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    NSDictionary* result = [self createDocWithAttachment: attach1 and: attach2];
    NSString* revID = result[@"rev"];

    // Now get the attachment via its URL:
    CBLResponse* response = SendRequest(self, @"GET", @"/db/doc1/attach", nil, nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual(response.body.asJSON, attach1);
    AssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    NSString* eTag = (response.headers)[@"Etag"];
    Assert(eTag.length > 0);
    
    // Ditto the 2nd attachment, whose name contains "/"s:
    response = SendRequest(self, @"GET", @"/db/doc1/path/to/attachment", nil, nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual(response.body.asJSON, attach2);
    AssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    eTag = (response.headers)[@"Etag"];
    Assert(eTag.length > 0);
    
    // A nonexistent attachment should result in a kCBLStatusNotFound:
    response = SendRequest(self, @"GET", @"/db/doc1/bogus", nil, nil);
    AssertEq(response.status, kCBLStatusNotFound);
    
    response = SendRequest(self, @"GET", @"/db/missingdoc/bogus", nil, nil);
    AssertEq(response.status, kCBLStatusNotFound);
    
    // Get the document with attachment data:
    response = SendRequest(self, @"GET", @"/db/doc1?attachments=true", nil, nil);
    Assert([response.headers[@"Content-Type"] hasPrefix: @"multipart/related;"]);

    response = SendRequest(self, @"GET", @"/db/doc1?attachments=true",
                           @{@"Accept": @"application/json"}, nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual((response.body)[@"_attachments"],
                $dict({@"attach", $dict({@"data", [CBLBase64 encode: attach1]},
                                        {@"content_type", @"text/plain"},
                                        {@"length", @(attach1.length)},
                                        {@"digest", @"sha1-gOHUOBmIMoDCrMuGyaLWzf1hQTE="},
                                        {@"revpos", @1})},
                       {@"path/to/attachment",
                                  $dict({@"data", [CBLBase64 encode: attach2]},
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
    result = SendBody(self, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
    revID = result[@"rev"];
    
    // Get the doc with attachments modified since rev #1:
    NSString* path = $sprintf(@"/db/doc1?attachments=true&atts_since=[%%22%@%%22]", revID);
    Send(self, @"GET", path, kCBLStatusOK, 
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"aloha"},
               {@"_attachments", $dict({@"attach", $dict({@"stub", $true}, 
                                                         {@"revpos", @1})},
                                       {@"path/to/attachment", $dict({@"stub", $true}, 
                                                                     {@"revpos", @1})})}));
}

- (void) test_GetJSONAttachment {
    // Create a document with two json-like attachments. One with be put as 'text/plain' and
    // the other one will be put as 'application/json'.
    NSData* attach1 = [@"{\"name\": \"foo\"}" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"{\"name\": \"bar\"}" dataUsingEncoding: NSUTF8StringEncoding];
    
    NSString* base641 = [CBLBase64 encode: attach1];
    NSString* base642 = [CBLBase64 encode: attach2];
    
    NSDictionary* attachmentDict = $dict({@"attach1", $dict({@"content_type", @"text/plain"},
                                                            {@"data", base641})},
                                         {@"attach2", $dict({@"content_type", @"application/json"},
                                                            {@"data", base642})});
    NSDictionary* props = $dict({@"message", @"hello"}, {@"_attachments", attachmentDict});
    
    SendBody(self, @"PUT", @"/db/doc1", props, kCBLStatusCreated, nil);
    
    // Get the first attachment
    CBLResponse* response = SendRequest(self, @"GET", @"/db/doc1/attach1", nil, nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual(response.body.asJSON, attach1);
    AssertEqual((response.headers)[@"Content-Type"], @"text/plain");
    NSString* eTag = (response.headers)[@"Etag"];
    Assert(eTag.length > 0);
    
    // Get the second attachment
    response = SendRequest(self, @"GET", @"/db/doc1/attach2", nil, nil);
    AssertEq(response.status, kCBLStatusOK);
    AssertEqual(response.body.asJSON, attach2);
    AssertEqual((response.headers)[@"Content-Type"], @"application/json");
    eTag = (response.headers)[@"Etag"];
    Assert(eTag.length > 0);
}

- (void) test_GetRange {
    NSData* attach1 = [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding];
    NSData* attach2 = [@"This is the body of path/to/attachment" dataUsingEncoding: NSUTF8StringEncoding];
    [self createDocWithAttachment: attach1 and: attach2];

    // 5-15:
    CBLResponse* response = SendRequest(self, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=5-15"}),
                                       nil);
    AssertEq(response.status, 206);
    AssertEqual((response.headers)[@"Content-Range"], @"bytes 5-15/27");
    AssertEqual(response.body.asJSON, [@"is the body" dataUsingEncoding: NSUTF8StringEncoding]);

    // 12-:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=12-"}),
                                       nil);
    AssertEq(response.status, 206);
    AssertEqual((response.headers)[@"Content-Range"], @"bytes 12-26/27");
    AssertEqual(response.body.asJSON, [@"body of attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    // 12-100:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                           $dict({@"Range", @"bytes=12-100"}),
                           nil);
    AssertEq(response.status, 206);
    AssertEqual((response.headers)[@"Content-Range"], @"bytes 12-26/27");
    AssertEqual(response.body.asJSON, [@"body of attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    // -7:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                                       $dict({@"Range", @"bytes=-7"}),
                                       nil);
    AssertEq(response.status, 206);
    AssertEqual((response.headers)[@"Content-Range"], @"bytes 20-26/27");
    AssertEqual(response.body.asJSON, [@"attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    NSString* eTag = (response.headers)[@"Etag"];
    Assert(eTag.length > 0);
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                           $dict({@"Range", @"bytes=-7"},
                                 {@"If-None-Match", eTag}),
                           nil);
    AssertEq(response.status, 304);

    // 5-3:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                           $dict({@"Range", @"bytes=5-3"}),
                           nil);
    AssertEq(response.status, 200);
    AssertNil((response.headers)[@"Content-Range"]);
    AssertEqual(response.body.asJSON, [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    // -100:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                           $dict({@"Range", @"bytes=-100"}),
                           nil);
    AssertEq(response.status, 200); // full range
    AssertNil((response.headers)[@"Content-Range"]);
    AssertEqual(response.body.asJSON, [@"This is the body of attach1" dataUsingEncoding: NSUTF8StringEncoding]);

    // 100-:
    response = SendRequest(self, @"GET", @"/db/doc1/attach",
                           $dict({@"Range", @"bytes=100-"}),
                           nil);
    AssertEq(response.status, 416);
    AssertEqual((response.headers)[@"Content-Range"], @"bytes */27");
    AssertNil(response.body);
}


- (void) test_PutMultipart {
    RequireTestCase(Docs);
    RequireTestCase(CBLMultipartDownloader);
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
    
    CBLResponse* response = SendRequest(self, @"PUT", @"/db/doc",
                           $dict({@"Content-Type", @"multipart/related; boundary=\"BOUNDARY\""}),
                                       [body dataUsingEncoding: NSUTF8StringEncoding]);
    AssertEq(response.status, kCBLStatusCreated);
}


#pragma mark - REVS:


- (void) test_OpenRevs {
    RequireTestCase(Databases);
    // PUT:
    NSDictionary* result = SendBody(self, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}),
                                    kCBLStatusCreated, nil);
    NSString* revID1 = result[@"rev"];
    
    // PUT to update:
    result = SendBody(self, @"PUT", @"/db/doc1",
                      $dict({@"message", @"goodbye"}, {@"_rev", revID1}), 
                      kCBLStatusCreated, nil);
    NSString* revID2 = result[@"rev"];
    
    Send(self, @"GET", @"/db/doc1?open_revs=all", kCBLStatusOK,
         $array( $dict({@"ok", $dict({@"_id", @"doc1"},
                                     {@"_rev", revID2},
                                     {@"message", @"goodbye"})}) ));
    Send(self, @"GET", $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, revID2), kCBLStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID2},
                                    {@"message", @"goodbye"})})
                ));
    NSString* uri = $sprintf(@"/db/doc1?open_revs=[%%22%@%%22,%%22%@%%22]", revID1, @"666-deadbeef");
    Send(self, @"GET", uri, kCBLStatusOK,
         $array($dict({@"ok", $dict({@"_id", @"doc1"},
                                    {@"_rev", revID1},
                                    {@"message", @"hello"})}),
                $dict({@"missing", @"666-deadbeef"})
                ));

    // We've been forcing JSON, but verify that open_revs defaults to multipart:
    CBLResponse* response = SendRequest(self, @"GET", uri, nil, nil);
    Assert([response.headers[@"Content-Type"] hasPrefix: @"multipart/mixed;"]);
}


- (void) test_RevsDiff {
    RequireTestCase(Databases);
    NSDictionary* doc1r1 = SendBody(self, @"PUT", @"/db/11111", $dict(), kCBLStatusCreated,nil);
    NSString* doc1r1ID = doc1r1[@"rev"];
    NSDictionary* doc2r1 = SendBody(self, @"PUT", @"/db/22222", $dict(), kCBLStatusCreated,nil);
    NSString* doc2r1ID = doc2r1[@"rev"];
    NSDictionary* doc3r1 = SendBody(self, @"PUT", @"/db/33333", $dict(), kCBLStatusCreated,nil);
    NSString* doc3r1ID = doc3r1[@"rev"];
    
    NSDictionary* doc1r2 = SendBody(self, @"PUT", @"/db/11111", $dict({@"_rev", doc1r1ID}), kCBLStatusCreated,nil);
    NSString* doc1r2ID = doc1r2[@"rev"];
    SendBody(self, @"PUT", @"/db/22222", $dict({@"_rev", doc2r1ID}), kCBLStatusCreated,nil);

    NSDictionary* doc1r3 = SendBody(self, @"PUT", @"/db/11111", $dict({@"_rev", doc1r2ID}), kCBLStatusCreated,nil);
    NSString* doc1r3ID = doc1r3[@"rev"];
    
    SendBody(self, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"3-f000"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-badbad"]},
                   {@"99999", @[@"6-666666"]}),
             kCBLStatusOK,
             $dict({@"11111", $dict({@"missing", @[@"3-f000"]},
                                    {@"possible_ancestors", @[doc1r2ID, doc1r1ID]})},
                   {@"33333", $dict({@"missing", @[@"10-badbad"]},
                                    {@"possible_ancestors", @[doc3r1ID]})},
                   {@"99999", $dict({@"missing", @[@"6-666666"]})}
                   ));
    
    // Compact the database -- this will null out the JSON of doc1r1 & doc1r2,
    // and they won't be returned as possible ancestors anymore.
    Send(self, @"POST", @"/db/_compact", kCBLStatusAccepted, nil);
    
    SendBody(self, @"POST", @"/db/_revs_diff",
             $dict({@"11111", @[doc1r2ID, @"4-f000"]},
                   {@"22222", @[doc2r1ID]},
                   {@"33333", @[@"10-badbad"]},
                   {@"99999", @[@"6-666666"]}),
             kCBLStatusOK,
             $dict({@"11111", $dict({@"missing", @[@"4-f000"]},
                                    {@"possible_ancestors", @[doc1r3ID]})},
                   {@"33333", $dict({@"missing", @[@"10-badbad"]},
                                    {@"possible_ancestors", @[doc3r1ID]})},
                   {@"99999", $dict({@"missing", @[@"6-666666"]})}
                   ));

    // Check the revision history using _revs_info:
    Send(self, @"GET", @"/db/11111?revs_info=true", 200,
          @{ @"_id" : @"11111", @"_rev": doc1r3ID,
             @"_revs_info": @[ @{ @"rev" : doc1r3ID, @"status": @"available" },
                               @{ @"rev" : doc1r2ID, @"status": @"missing" },
                               @{ @"rev" : doc1r1ID, @"status": @"missing" }
         ]});

    // Check the revision history using _revs:
    Send(self, @"GET", @"/db/11111?revs=true", 200,
         @{ @"_id" : @"11111", @"_rev": doc1r3ID,
            @"_revisions": @{
                @"start": @3,
                @"ids": @[ [doc1r3ID substringFromIndex: 2], [doc1r2ID substringFromIndex: 2],
                           [doc1r1ID substringFromIndex: 2] ]
         } } );
}


- (void) test_AccessCheck {
    RequireTestCase(Databases);
    NSURL* url = [NSURL URLWithString: @"cbl:///db/"];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = @"GET";
    CBL_Router* router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    Assert(router!=nil);
    __block BOOL calledOnAccessCheck = NO;
    router.onAccessCheck = ^CBLStatus(CBLDatabase* accessDB, NSString* docID, SEL action) {
        Assert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 200;
    };
    [router start];
    Assert(calledOnAccessCheck);
    Assert(router.response.status == 200);
    
    router = [[CBL_Router alloc] initWithDatabaseManager: dbmgr request: request];
    Assert(router!=nil);
    calledOnAccessCheck = NO;
    router.onAccessCheck = ^CBLStatus(CBLDatabase* accessDB, NSString* docID, SEL action) {
        Assert([accessDB.name isEqualToString: @"db"]);
        calledOnAccessCheck = YES;
        return 401;
    };
    [router start];
    
    Assert(calledOnAccessCheck);
    Assert(router.response.status == 401);
}


- (void) test_URLProtocol_Registration {
    [CBL_URLProtocol forgetServers];
    AssertNil([CBL_URLProtocol serverForHostname: @"some.hostname"]);
    
    NSURL* url = [NSURL URLWithString: @"cbl://some.hostname/"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    AssertNil(body);
    AssertEqual(error.domain, NSURLErrorDomain);
    AssertEq(error.code, NSURLErrorCannotFindHost);
    
    CBL_Server* server = [CBL_RunLoopServer createEmptyAtTemporaryPath: @"CBL_URLProtocolTest"];
    NSURL* root = [CBL_URLProtocol registerServer: server forHostname: @"some.hostname"];
    AssertEqual(root, url);
    AssertEq([CBL_URLProtocol serverForHostname: @"some.hostname"], server);
    
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    Assert(body != nil);
    Assert(response != nil);
    AssertEq(response.statusCode, kCBLStatusOK);
    
    [server close];
    [CBL_URLProtocol registerServer: nil forHostname: @"some.hostname"];
    body = [NSURLConnection sendSynchronousRequest: req 
                                 returningResponse: &response 
                                             error: &error];
    AssertNil(body);
    AssertEqual(error.domain, NSURLErrorDomain);
    AssertEq(error.code, NSURLErrorCannotFindHost);
}


- (void) test_URLProtocol {
    RequireTestCase(CBL_Router);
    [CBL_URLProtocol forgetServers];
    CBL_Server* server = [CBL_RunLoopServer createEmptyAtTemporaryPath: @"CBL_URLProtocolTest"];
    [CBL_URLProtocol setServer: server];
    
    NSURL* url = [NSURL URLWithString: @"cbl:///"];
    NSURLRequest* req = [NSURLRequest requestWithURL: url];
    NSHTTPURLResponse* response = nil;
    NSError* error = nil;
    NSData* body = [NSURLConnection sendSynchronousRequest: req 
                                         returningResponse: &response 
                                                     error: &error];
    NSString* bodyStr = [[NSString alloc] initWithData: body encoding: NSUTF8StringEncoding];
    Log(@"Response = %@", response);
    Log(@"MIME Type = %@", response.MIMEType);
    Log(@"Body = %@", bodyStr);
    Assert(body != nil);
    Assert(response != nil);
    AssertEq(response.statusCode, kCBLStatusOK);
    AssertEqual((response.allHeaderFields)[@"Content-Type"], @"application/json");
    Assert([bodyStr rangeOfString: @"\"CouchbaseLite\":\"Welcome\""].length > 0
            || [bodyStr rangeOfString: @"\"CouchbaseLite\": \"Welcome\""].length > 0);
    [server close];
    [CBL_URLProtocol setServer: nil];
}

#pragma mark - Validation:

- (void) test_ValidationMessage {
    [db setValidationNamed: @"onlyMyDocs"
                   asBlock: ^(CBLRevision *rev, id<CBLValidationContext> context) {
                       if (!rev.isDeletion) {
                           if (![rev.properties[@"type"] isEqualToString:@"doc"])
                               [context reject];
                           else if (![rev.properties[@"from"] isEqualToString:@"me"])
                               [context rejectWithMessage: @"This is not a user doc."];
                       } else {
                           BOOL allowed = [rev.parentRevision.properties[@"allow_delete"] boolValue];
                           if (!allowed)
                               [context rejectWithMessage: @"This document cannot be deleted."];
                       }
    }];

    NSDictionary* result;

    // do_POST OK:
    result = SendBody(self, @"POST", @"/db",
             $dict({@"type", @"doc"},
                   {@"from", @"me"},
                   {@"title", @"doc1"}), kCBLStatusCreated, nil);
    Assert(result[@"ok"] != nil);
    Assert(result[@"id"] != nil);
    Assert(result[@"rev"] != nil);

    // do_POST forbidden, default message:
    result = SendBody(self, @"POST", @"/db",
                      $dict({@"type", @"nondoc"},
                            {@"from", @"me"},
                            {@"title", @"nondoc1"}), kCBLStatusForbidden, nil);
    AssertNil(result[@"rev"]);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"invalid document");

    // do_POST forbidden, custom message:
    result = SendBody(self, @"POST", @"/db",
                      $dict({@"type", @"doc"},
                            {@"from", @"you"},
                            {@"title", @"doc2"}), kCBLStatusForbidden, nil);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"This is not a user doc.");

    // do_PUT OK:
    result = SendBody(self, @"PUT", @"/db/doc3",
                      $dict({@"type", @"doc"},
                            {@"from", @"me"},
                            {@"title", @"doc3"}), kCBLStatusCreated, nil);
    Assert(result[@"ok"] != nil);
    Assert(result[@"id"] != nil);
    Assert(result[@"rev"] != nil);

    // do_PUT forbidden, default message:
    result = SendBody(self, @"PUT", @"/db/doc4",
                      $dict({@"type", @"nondoc"},
                            {@"from", @"me"},
                            {@"title", @"doc4"}), kCBLStatusForbidden, nil);
    AssertNil(result[@"rev"]);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"invalid document");

    // do_PUT forbidden, custom message:
    result = SendBody(self, @"PUT", @"/db/doc5",
                      $dict({@"type", @"doc"},
                            {@"from", @"you"},
                            {@"title", @"doc5"}), kCBLStatusForbidden, nil);
    AssertNil(result[@"rev"]);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"This is not a user doc.");

    // do_POST_bulk_docs, OK:
    NSArray* bulkResult;
    bulkResult = SendBody(self, @"POST", @"/db/_bulk_docs",
                          $dict({@"docs", $array($dict({@"type", @"doc"},
                                                       {@"from", @"me"},
                                                       {@"title", @"doc6"}),
                                                 $dict({@"type", @"doc"},
                                                       {@"from", @"me"},
                                                       {@"title", @"doc7"})
                                                 )}), kCBLStatusCreated, nil);
    AssertEq((int)bulkResult.count, 2);
    for (NSDictionary *r in bulkResult) {
        Assert(r[@"ok"] != nil);
        Assert(r[@"id"] != nil);
        Assert(r[@"rev"] != nil);
    }

    // do_POST_bulk_docs, mixed result:
    bulkResult = SendBody(self, @"POST", @"/db/_bulk_docs",
                          $dict({@"docs", $array($dict({@"type", @"doc"},
                                                       {@"from", @"me"},
                                                       {@"title", @"doc8"}),
                                                 $dict({@"type", @"nondoc"},
                                                       {@"from", @"me"},
                                                       {@"title", @"doc9"}),
                                                 $dict({@"type", @"doc"},
                                                       {@"from", @"you"},
                                                       {@"title", @"doc10"})
                                                 )}), kCBLStatusCreated, nil);
    AssertEq((int)bulkResult.count, 3);
    Assert(bulkResult[0][@"ok"] != nil);
    Assert(bulkResult[0][@"id"] != nil);
    Assert(bulkResult[0][@"rev"] != nil);
    AssertEqual(bulkResult[1][@"status"], @(403));
    AssertEqual(bulkResult[1][@"error"], @"forbidden");
    AssertEqual(bulkResult[1][@"reason"], @"invalid document");
    AssertEqual(bulkResult[2][@"status"], @(403));
    AssertEqual(bulkResult[2][@"error"], @"forbidden");
    AssertEqual(bulkResult[2][@"reason"], @"This is not a user doc.");

    // do_POST_bulk_docs, all_or_nothing=true
    result = SendBody(self, @"POST", @"/db/_bulk_docs",
                      $dict({@"all_or_nothing", @"true"},
                            {@"docs", $array($dict({@"type", @"doc"},
                                                   {@"from", @"me"},
                                                   {@"title", @"doc11"}),
                                             $dict({@"type", @"nondoc"},
                                                   {@"from", @"me"},
                                                   {@"title", @"doc12"}),
                                             $dict({@"type", @"doc"},
                                                   {@"from", @"you"},
                                                   {@"title", @"doc13"})
                                             )}), kCBLStatusForbidden, nil);
    AssertNil(result[@"rev"]);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"invalid document");

    // do_DELETE
    result = SendBody(self, @"PUT", @"/db/doc14",
                      $dict({@"type", @"doc"},
                            {@"from", @"me"},
                            {@"title", @"doc14"},
                            {@"allow_delete", $false}), kCBLStatusCreated, nil);
    NSString* doc14RevID = result[@"rev"];
    Assert(doc14RevID != nil);
    result = Send(self, @"DELETE", $sprintf(@"/db/doc14?rev=%@", doc14RevID),
                  kCBLStatusForbidden, nil);
    AssertEqual(result[@"status"], @(403));
    AssertEqual(result[@"error"], @"forbidden");
    AssertEqual(result[@"reason"], @"This document cannot be deleted.");
}

@end
