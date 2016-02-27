//
//  CBLMultipartDownloader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
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


UsingLogDomain(Sync);


@implementation CBLMultipartDownloader


- (instancetype) initWithURL: (NSURL*)url
                    database: (CBLDatabase*)database
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    self = [super initWithMethod: @"GET" 
                             URL: url 
                            body: nil
                    onCompletion: onCompletion];
    if (self) {
        _db = database;

        [_request setValue: @"multipart/related, application/json" forHTTPHeaderField: @"Accept"];
        [_request setValue: @"gzip" forHTTPHeaderField: @"X-Accept-Part-Encoding"];
    }
    return self;
}


- (NSString*) description {
    return $sprintf(@"%@[%@]", [self class], _request.URL.path);
}


- (NSDictionary*) document {
    return _reader.document;
}


#pragma mark - URL CONNECTION CALLBACKS:


- (void) didReceiveResponse:(NSHTTPURLResponse *)response {
    [super didReceiveResponse: response];
    _reader = [[CBLMultipartDocumentReader alloc] initWithDatabase: _db];
    if (_status < 300) {
        NSDictionary* headers = _responseHeaders;
        // If we let the reader see the Content-Encoding header it might decide to un-gzip the
        // data, but it's already been decoded by NSURLConnection! So remove that header:
        if (headers[@"Content-Encoding"]) {
            NSMutableDictionary* nuHeaders = [headers mutableCopy];
            [nuHeaders removeObjectForKey: @"Content-Encoding"];
            headers = nuHeaders;
        }
        // Check the content type to see whether it's a multipart response:
        if (![_reader setHeaders: headers]) {
            LogTo(RemoteRequest, @"%@ got invalid Content-Type", self);
            [self cancelWithStatus: _reader.status message: @"Received invalid Content-Type"];
            return;
        }
    }
}


- (void) didReceiveData:(NSData *)data {
    [super didReceiveData: data];
    if (![_reader appendData: data])
        [self cancelWithStatus: _reader.status message: @"Received invalid multipart response"];
}


- (void) didFinishLoading {
    LogVerbose(Sync, @"%@: Finished loading (%u attachments)",
          self, (unsigned)_reader.attachmentCount);
    if (![_reader finish]) {
        [self cancelWithStatus: _reader.status message: @"Received invalid multipart response"];
        return;
    }
    
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


@end
