//
//  TDPuller_Tests.m
//  TouchDB
//
//  Created by Jens Alfke on 12/7/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDPuller.h"
#import "TDPusher.h"
#import "TDServer.h"
#import "TDDatabase+Insertion.h"
#import "TDInternal.h"
#import "Test.h"


#if DEBUG


#define kRemoteDBURLStr @"http://localhost:5984/tdreplicator_test"


static void deleteRemoteDB(void) {
    Log(@"Deleting %@", kRemoteDBURLStr);
    NSURL* url = [NSURL URLWithString: kRemoteDBURLStr];
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL: url
                                                       cachePolicy: NSURLRequestUseProtocolCachePolicy
                                                   timeoutInterval: 10.0];
    req.HTTPMethod = @"DELETE";
    NSURLResponse* response = nil;
    NSError* error = nil;
    [NSURLConnection sendSynchronousRequest: req returningResponse: &response error: &error];
    CAssert(error == nil || error.code == 404, @"Couldn't delete remote: %@", error);
}


static NSString* replic8(TDDatabase* db, NSString* urlStr, BOOL push, NSString* lastSequence) {
    NSURL* remote = [NSURL URLWithString: urlStr];
    TDReplicator* repl = [[[TDReplicator alloc] initWithDB: db remote: remote
                                                        push: push continuous: NO] autorelease];
    if (push)
        ((TDPusher*)repl).createTarget = YES;
    [repl start];
    
    CAssert(repl.running);
    Log(@"Waiting for replicator to finish...");
    while (repl.running) {
        if (![[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                      beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]])
            break;
    }
    CAssert(!repl.running);
    return repl.lastSequence;
}


TestCase(TDPusher) {
    RequireTestCase(TDDatabase);
    TDServer* server = [TDServer createEmptyAtPath: @"/tmp/TDPusherTest"];
    TDDatabase* db = [server databaseNamed: @"db"];
    [db open];
    
    deleteRemoteDB();

    // Create some documents:
    NSMutableDictionary* props = $mdict({@"_id", @"doc1"},
                                        {@"foo", $object(1)}, {@"bar", $false});
    TDStatus status;
    TDRevision* rev1 = [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    [props setObject: rev1.revID forKey: @"_rev"];
    [props setObject: $true forKey: @"UPDATED"];
    TDRevision* rev2 = [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: rev1.revID allowConflict: NO status: &status];
    CAssertEq(status, 201);
    
    props = $mdict({@"_id", @"doc2"},
                   {@"baz", $object(666)}, {@"fnord", $true});
    [db putRevision: [TDRevision revisionWithProperties: props]
                        prevRevisionID: nil allowConflict: NO status: &status];
    CAssertEq(status, 201);
#pragma unused(rev2)
    
    // Push them to the remote:
    id lastSeq = replic8(db, kRemoteDBURLStr, YES, nil);
    CAssertEqual(lastSeq, @"3");
}


TestCase(TDPuller) {
    RequireTestCase(TDPusher);
    TDServer* server = [TDServer createEmptyAtPath: @"/tmp/TDPullerTest"];
    TDDatabase* db = [server databaseNamed: @"db"];
    [db open];
    
    id lastSeq = replic8(db, kRemoteDBURLStr, NO, nil);
    CAssertEqual(lastSeq, @"2");
    
    CAssertEq(db.documentCount, 2u);
    CAssertEq(db.lastSequence, 3);
    
    replic8(db, kRemoteDBURLStr, NO, lastSeq);
    CAssertEq(db.lastSequence, 3);
    
    TDRevision* doc = [db getDocumentWithID: @"doc1" revisionID: nil options: 0];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"2-"]);
    CAssertEqual([doc.properties objectForKey: @"foo"], $object(1));
    
    doc = [db getDocumentWithID: @"doc2" revisionID: nil options: 0];
    CAssert(doc);
    CAssert([doc.revID hasPrefix: @"1-"]);
    CAssertEqual([doc.properties objectForKey: @"fnord"], $true);
}

#endif
