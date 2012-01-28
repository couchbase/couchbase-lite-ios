//
//  TDRemoteRequest.m
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDRemoteRequest.h"
#import "TDMisc.h"


@implementation TDRemoteRequest


- (id) initWithMethod: (NSString*)method URL: (NSURL*)url body: (id)body
         onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    self = [super init];
    if (self) {
        LogTo(RemoteRequest, @"%@: %@ .%@", self, method, url);
        _onCompletion = [onCompletion copy];
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;
        _request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [_request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
        if (body) {
            _request.HTTPBody = [NSJSONSerialization dataWithJSONObject: body options: 0 error: nil];
            [_request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
        }
        
        _connection = [[NSURLConnection connectionWithRequest: _request delegate: self] retain];
        [_connection start];
    }
    return self;
}


- (void) clearConnection {
    [_request release];
    _request = nil;
    [_connection autorelease];
    _connection = nil;
    [_inputBuffer release];
    _inputBuffer = nil;
}


- (void)dealloc {
    [self clearConnection];
    [_onCompletion release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@ %@]", [self class], _request.HTTPMethod, _request.URL);
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    Assert(result || error);
    LogTo(RemoteRequest, @"%@: Calling completion block...", self);
    _onCompletion(result, error);
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    int status = (int) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(RemoteRequest, @"%@: Got response, status %d", self, status);
    if (status >= 300) {
        [_connection cancel];
        [self connection: connection didFailWithError: TDHTTPError(status, _request.URL)];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(RemoteRequest, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    if (!_inputBuffer)
        _inputBuffer = [[NSMutableData alloc] initWithCapacity: MAX(data.length, 8192u)];
    [_inputBuffer appendData: data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    Log(@"%@: Got error %@", self, error);
    [self clearConnection];
    [self respondWithResult: nil error: error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    id result = [NSJSONSerialization JSONObjectWithData: _inputBuffer options: 0 error:nil];
    NSError* error = nil;
    if (!result) {
        Warn(@"%@: %@ %@ returned unparseable data '%@'",
             self, _request.HTTPMethod, _request.URL, [_inputBuffer my_UTF8ToString]);
        error = TDHTTPError(502, _request.URL);
    }
    [self clearConnection];
    [self respondWithResult: result error: error];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}

@end
