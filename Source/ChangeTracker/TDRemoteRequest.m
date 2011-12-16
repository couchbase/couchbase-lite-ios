//
//  TDRemoteRequest.m
//  TouchDB
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"

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


- (void) respondWithResult: (id)result error: (NSError*)error {
    LogTo(RemoteRequest, @"%@: Calling completion block...");
    _onCompletion(result, error);
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    int status = (int) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(RemoteRequest, @"%@: Got response, status %d", self, status);
    if (status >= 300) {
        [_connection cancel];
        NSError* error = [NSError errorWithDomain: @"HTTP" code: status userInfo:nil];
        [self connection: connection didFailWithError: error];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(RemoteRequest, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    if (!_inputBuffer)
        _inputBuffer = [[NSMutableData alloc] initWithCapacity: MAX(data.length, 8192)];
    [_inputBuffer appendData: data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    Warn(@"%@: Got error %@", self, error);
    [self clearConnection];
    [self respondWithResult: nil error: error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    id result = [NSJSONSerialization JSONObjectWithData: _inputBuffer options: 0 error:nil];
    if (!result) {
        Warn(@"%@: %@ %@ returned unparseable data '%@'",
             self, _request.HTTPMethod, _request.URL, [_inputBuffer my_UTF8ToString]);
    }
    [self clearConnection];
    [self respondWithResult: result error: nil];
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}

@end
