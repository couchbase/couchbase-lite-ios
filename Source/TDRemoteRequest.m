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
#import "TDBlobStore.h"
#import <TouchDB/TDDatabase.h>
#import "TDRouter.h"
#import "TDReplicator.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"


// Max number of retry attempts for a transient failure
#define kMaxRetries 2


@implementation TDRemoteRequest


- (id) initWithMethod: (NSString*)method URL: (NSURL*)url body: (id)body
           authorizer: (id<TDAuthorizer>)authorizer
         onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    self = [super init];
    if (self) {
        _onCompletion = [onCompletion copy];
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;
        _request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        [_request setValue: $sprintf(@"TouchDB/%@", [TDRouter versionString])
                  forHTTPHeaderField:@"User-Agent"];
        
        LogTo(RemoteRequest, @"%@: Starting...", self);
        [self setupRequest: _request withBody: body];
        
        NSString* authHeader = [authorizer authorizeURLRequest: _request];
        if (authHeader)
            [_request setValue: authHeader forHTTPHeaderField: @"Authorization"];
        
        [self start];
    }
    return self;
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
}


- (void) dontLog404 {
    _dontLog404 = true;
}


- (void) start {
    Assert(!_connection);
    _connection = [[NSURLConnection connectionWithRequest: _request delegate: self] retain];
    // Retaining myself shouldn't be necessary, because NSURLConnection is documented as retaining
    // its delegate while it's running. But GNUstep doesn't (currently) do this, so for
    // compatibility I retain myself until the connection completes (see -clearConnection.)
    // TEMP: Remove this and the [self autorelease] below when I get the fix from GNUstep.
    [self retain];
}


- (void) clearConnection {
    [_request release];
    _request = nil;
    if (_connection) {
        [_connection autorelease];
        _connection = nil;
        [self autorelease];  // balances [self retain] in -start method
    }
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
    _onCompletion(result, error);
}


- (void) cancelWithStatus: (int)status {
    [_connection cancel];

    if (status >= 500 && status != 501 && status <= 504 && _retryCount < kMaxRetries) {
        // Retry on Internal Server Error, Bad Gateway, Service Unavailable or Gateway Timeout:
        NSTimeInterval delay = 1<<_retryCount;
        ++_retryCount;
        LogTo(RemoteRequest, @"%@: Will retry in %g sec", self, delay);
        [_connection autorelease];
        _connection = nil;
        [self performSelector: @selector(start) withObject: nil afterDelay: delay];
        return;
    }
    
    [self connection: _connection didFailWithError: TDStatusToNSError(status, _request.URL)];
}


#pragma mark - NSURLCONNECTION DELEGATE:


- (void)connection:(NSURLConnection *)connection
        willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    LogTo(RemoteRequest, @"Got challenge: %@", challenge);
    [challenge.sender performDefaultHandlingForAuthenticationChallenge: challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    int status = (int) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(RemoteRequest, @"%@: Got response, status %d", self, status);
    if (TDStatusIsError(status)) 
        [self cancelWithStatus: status];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(RemoteRequest, @"%@: Got %lu bytes", self, (unsigned long)data.length);
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (WillLog()) {
        if (!(_dontLog404 && error.code == kTDStatusNotFound && $equal(error.domain, TDHTTPErrorDomain)))
            Log(@"%@: Got error %@", self, error);
    }
    [self clearConnection];
    [self respondWithResult: nil error: error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LogTo(RemoteRequest, @"%@: Finished loading", self);
    [self clearConnection];
    [self respondWithResult: self error: nil];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}

@end




@implementation TDRemoteJSONRequest

- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    if (body) {
        request.HTTPBody = [TDJSON dataWithJSONObject: body options: 0 error: NULL];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
}

- (void) clearConnection {
    [_jsonBuffer release];
    _jsonBuffer = nil;
    [super clearConnection];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [super connection: connection didReceiveData: data];
    if (!_jsonBuffer)
        _jsonBuffer = [[NSMutableData alloc] initWithCapacity: MAX(data.length, 8192u)];
    [_jsonBuffer appendData: data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LogTo(RemoteRequest, @"%@: Finished loading", self);
    id result = nil;
    if (_jsonBuffer)
        result = [TDJSON JSONObjectWithData: _jsonBuffer options: 0 error: NULL];
    NSError* error = nil;
    if (!result) {
        Warn(@"%@: %@ %@ returned unparseable data '%@'",
             self, _request.HTTPMethod, _request.URL, [_jsonBuffer my_UTF8ToString]);
        error = TDStatusToNSError(kTDStatusUpstreamError, _request.URL);
    }
    [self clearConnection];
    [self respondWithResult: result error: error];
}

@end
