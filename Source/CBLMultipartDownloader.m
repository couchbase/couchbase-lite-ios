//
//  CBLMultipartDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMultipartDownloader.h"
#import "CBLMultipartDocumentReader.h"
#import "CBL_BlobStore.h"
#import "CBLInternal.h"
#import "CBLMisc.h"
#import "CollectionUtils.h"


@implementation CBLMultipartDownloader


- (instancetype) initWithURL: (NSURL*)url
                    database: (CBLDatabase*)database
              requestHeaders: (NSDictionary *) requestHeaders
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    self = [super initWithMethod: @"GET" 
                             URL: url 
                            body: nil
                  requestHeaders: requestHeaders
                    onCompletion: onCompletion];
    if (self) {
        _db = database;
    }
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _request.URL.path);
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    [request setValue: @"multipart/related, application/json" forHTTPHeaderField: @"Accept"];
    request.HTTPBody = body;
}




- (NSDictionary*) document {
    return _reader.document;
}


#pragma mark - URL CONNECTION CALLBACKS:


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _reader = [[CBLMultipartDocumentReader alloc] initWithDatabase: _db];
    CBLStatus status = (CBLStatus) ((NSHTTPURLResponse*)response).statusCode;
    if (status < 300) {
        // Check the content type to see whether it's a multipart response:
        NSDictionary* headers = [(NSHTTPURLResponse*)response allHeaderFields];
        NSString* contentType = headers[@"Content-Type"];
        if ([contentType hasPrefix: @"text/plain"])
            contentType = nil;      // Workaround for CouchDB returning JSON docs with text/plain type
        if (![_reader setContentType: contentType]) {
            LogTo(RemoteRequest, @"%@ got invalid Content-Type '%@'", self, contentType);
            [self cancelWithStatus: _reader.status];
            return;
        }
    }
    
    [super connection: connection didReceiveResponse: response];
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [super connection: connection didReceiveData: data];
    if (![_reader appendData: data])
        [self cancelWithStatus: _reader.status];
}


- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LogTo(SyncVerbose, @"%@: Finished loading (%u attachments)",
          self, (unsigned)_reader.attachmentCount);
    if (![_reader finish]) {
        [self cancelWithStatus: _reader.status];
        return;
    }
    
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


@end



#if DEBUG
TestCase(CBLMultipartDownloader) {
    //These URLs only work for me!
    if (!$equal(NSUserName(), @"snej"))
        return;
    
    RequireTestCase(CBL_BlobStore);
    RequireTestCase(CBLMultipartReader_Simple);
    RequireTestCase(CBLMultipartReader_Types);
    
    CBLDatabase* db = [CBLDatabase createEmptyDBAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: @"CBLMultipartDownloader"]];
    //NSString* urlStr = @"http://127.0.0.1:5984/demo-shopping-attachments/2F9078DF-3C72-44C2-8332-B07B3A29FFE4"
    NSString* urlStr = @"http://127.0.0.1:5984/attach-test/oneBigAttachment";
    urlStr = [urlStr stringByAppendingString: @"?revs=true&attachments=true"];
    NSURL* url = [NSURL URLWithString: urlStr];
    __block BOOL done = NO;
    [[[CBLMultipartDownloader alloc] initWithURL: url
                                       database: db
                                 requestHeaders: nil
                                   onCompletion: ^(id result, NSError * error)
     {
         CAssertNil(error);
         CBLMultipartDownloader* request = result;
         Log(@"Got document: %@", request.document);
         NSDictionary* attachments = (request.document)[@"_attachments"];
         CAssert(attachments.count >= 1);
         CAssertEq(db.attachmentStore.count, 0u);
         for (NSDictionary* attachment in attachments.allValues) {
             CBL_BlobStoreWriter* writer = [db attachmentWriterForAttachment: attachment];
             CAssert(writer);
             CAssert([writer install]);
             NSData* blob = [db.attachmentStore blobForKey: writer.blobKey];
             Log(@"Found %u bytes of data for attachment %@", (unsigned)blob.length, attachment);
             NSNumber* lengthObj = attachment[@"encoded_length"] ?: attachment[@"length"];
             CAssertEq(blob.length, [lengthObj unsignedLongLongValue]);
             CAssertEq(writer.length, blob.length);
         }
         CAssertEq(db.attachmentStore.count, attachments.count);
         done = YES;
    }] start];
    
    while (!done)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
}
#endif
