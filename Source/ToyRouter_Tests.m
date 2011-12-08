//
//  ToyRouter_Tests.m
//  ToyCouch
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyRouter.h"
#import "ToyDB.h"
#import "ToyServer.h"
#import "CollectionUtils.h"
#import "Test.h"


#if DEBUG
#pragma mark - TESTS

static id SendBody(ToyServer* server, NSString* method, NSString* path, id bodyObj,
               int expectedStatus, id expectedResult) {
    NSURL* url = [NSURL URLWithString: [@"toy://" stringByAppendingString: path]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: url];
    request.HTTPMethod = method;
    if (bodyObj) {
        NSError* error = nil;
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject: bodyObj options:0 error:&error];
        CAssertNil(error);
    }
    ToyRouter* router = [[ToyRouter alloc] initWithServer: server request: request];
    CAssert(router!=nil);
    [router start];
    ToyResponse* response = router.response;
    NSData* json = response.body.asJSON;
    NSString* jsonStr = nil;
    id result = nil;
    if (json) {
        jsonStr = [[[NSString alloc] initWithData: json encoding: NSUTF8StringEncoding] autorelease];
        CAssert(jsonStr);
        NSError* error;
        result = [NSJSONSerialization JSONObjectWithData: json options: 0 error: &error];
        CAssert(result, @"Couldn't parse JSON response: %@", error);
    }
    Log(@"%@ %@ --> %d %@", method, path, response.status, jsonStr);
    
    CAssertEq(response.status, expectedStatus);

    if (expectedResult)
        CAssertEqual(result, expectedResult);
    [router release];
    return result;
}

static id Send(ToyServer* server, NSString* method, NSString* path,
               int expectedStatus, id expectedResult) {
    return SendBody(server, method, path, nil, expectedStatus, expectedResult);
}


TestCase(ToyRouter_Server) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"GET", @"/", 200, $dict({@"ToyCouch", @"welcome"},
                                          {@"version", kToyVersionString}));
    Send(server, @"GET", @"/_all_dbs", 200, $array());
    Send(server, @"GET", @"/non-existent", 404, nil);
    Send(server, @"GET", @"/BadName", 400, nil);
    Send(server, @"PUT", @"/", 400, nil);
    Send(server, @"POST", @"/", 400, nil);
}


TestCase(ToyRouter_Databases) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/database", 201, nil);
    Send(server, @"GET", @"/database", 200,
         $dict({@"db_name", @"database"}, {@"num_docs", $object(0)}, {@"update_seq", $object(0)}));
    Send(server, @"PUT", @"/database", 412, nil);
    Send(server, @"PUT", @"/database2", 201, nil);
    Send(server, @"GET", @"/_all_dbs", 200, $array(@"database", @"database2"));
    Send(server, @"GET", @"/database2", 200,
         $dict({@"db_name", @"database2"}, {@"num_docs", $object(0)}, {@"update_seq", $object(0)}));
    Send(server, @"DELETE", @"/database2", 200, nil);
    Send(server, @"GET", @"/_all_dbs", 200, $array(@"database"));
}


TestCase(ToyRouter_Docs) {
    // PUT:
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/db", 201, nil);
    NSDictionary* result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 
                                    201, nil);
    NSString* revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"1-"]);

    // PUT to update:
    result = SendBody(server, @"PUT", $sprintf(@"/db/doc1?rev=%@", revID),
                                    $dict({@"message", @"goodbye"}), 
                                    201, nil);
    Log(@"PUT returned %@", result);
    revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"2-"]);
    
    Send(server, @"GET", @"/db/doc1", 200,
         $dict({@"_id", @"doc1"}, {@"_rev", revID}, {@"message", @"goodbye"}));
    
    // Add more docs:
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"hello"}), 
                                    201, nil);
    NSString* revID3 = [result objectForKey: @"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hello"}), 
                                    201, nil);
    NSString* revID2 = [result objectForKey: @"rev"];

    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", 200, nil);
    CAssertEqual([result objectForKey: @"total_rows"], $object(3));
    CAssertEqual([result objectForKey: @"offset"], $object(0));
    NSArray* rows = [result objectForKey: @"rows"];
    CAssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));

    // DELETE:
    result = Send(server, @"DELETE", $sprintf(@"/db/doc1?rev=%@", revID), 200, nil);
    revID = [result objectForKey: @"rev"];
    CAssert([revID hasPrefix: @"3-"]);

    Send(server, @"GET", @"/db/doc1", 404, nil);
    
    // _changes:
    result = Send(server, @"GET", @"/db/_changes", 200,
                  $dict({@"last_seq", $object(5)},
                        {@"results", $array($dict({@"id", @"doc3"},
                                                  {@"rev", revID3},
                                                  {@"seq", $object(3)}),
                                            $dict({@"id", @"doc2"},
                                                  {@"rev", revID2},
                                                  {@"seq", $object(4)}),
                                            $dict({@"id", @"doc1"},
                                                  {@"rev", revID},
                                                  {@"seq", $object(5)},
                                                  {@"deleted", $true}))}));
    
    // _changes with ?since:
    result = Send(server, @"GET", @"/db/_changes?since=4", 200,
                  $dict({@"last_seq", $object(5)},
                        {@"results", $array($dict({@"id", @"doc1"},
                                                  {@"rev", revID},
                                                  {@"seq", $object(5)},
                                                  {@"deleted", $true}))}));
    result = Send(server, @"GET", @"/db/_changes?since=5", 200,
                  $dict({@"last_seq", $object(5)},
                        {@"results", $array()}));
}


TestCase(ToyRouter_AllDocs) {
    // PUT:
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/db", 201, nil);
    
    NSDictionary* result;
    result = SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 201, nil);
    NSString* revID = [result objectForKey: @"rev"];
    result = SendBody(server, @"PUT", @"/db/doc3", $dict({@"message", @"bonjour"}), 201, nil);
    NSString* revID3 = [result objectForKey: @"rev"];
    result = SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"guten tag"}), 201, nil);
    NSString* revID2 = [result objectForKey: @"rev"];
    
    // _all_docs:
    result = Send(server, @"GET", @"/db/_all_docs", 200, nil);
    CAssertEqual([result objectForKey: @"total_rows"], $object(3));
    CAssertEqual([result objectForKey: @"offset"], $object(0));
    NSArray* rows = [result objectForKey: @"rows"];
    CAssertEqual(rows, $array($dict({@"id",  @"doc1"}, {@"key", @"doc1"},
                                    {@"value", $dict({@"rev", revID})}),
                              $dict({@"id",  @"doc2"}, {@"key", @"doc2"},
                                    {@"value", $dict({@"rev", revID2})}),
                              $dict({@"id",  @"doc3"}, {@"key", @"doc3"},
                                    {@"value", $dict({@"rev", revID3})})
                              ));
    
    // ?include_docs:
    result = Send(server, @"GET", @"/db/_all_docs?include_docs=true", 200, nil);
    CAssertEqual([result objectForKey: @"total_rows"], $object(3));
    CAssertEqual([result objectForKey: @"offset"], $object(0));
    rows = [result objectForKey: @"rows"];
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
}


TestCase(ToyRouter_ContinuousChanges) {
    ToyServer* server = [ToyServer createEmptyAtPath: @"/tmp/ToyRouterTest"];
    Send(server, @"PUT", @"/db", 201, nil);

    SendBody(server, @"PUT", @"/db/doc1", $dict({@"message", @"hello"}), 201, nil);

    __block ToyResponse* response = nil;
    __block NSMutableData* body = [NSMutableData data];
    __block BOOL finished = NO;
    
    NSURL* url = [NSURL URLWithString: @"toy:///db/_changes?mode=continuous"];
    NSURLRequest* request = [NSURLRequest requestWithURL: url];
    ToyRouter* router = [[ToyRouter alloc] initWithServer: server request: request];
    router.onResponseReady = ^(ToyResponse* routerResponse) {
        CAssert(!response);
        response = routerResponse;
    };
    router.onDataAvailable = ^(NSData* content) {
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
    CAssertEq(response.status, 200);
    CAssert(body.length > 0);
    CAssert(!finished);
    [body setLength: 0];
    
    // Now make a change to the database:
    SendBody(server, @"PUT", @"/db/doc2", $dict({@"message", @"hej"}), 201, nil);

    // Should now have received additional output from the router:
    CAssert(body.length > 0);
    CAssert(!finished);
    
    [router stop];
    [router release];
}

#endif
