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
#import "TDAuthorizer.h"
#import "TDMisc.h"
#import "TDBlobStore.h"
#import <TouchDB/TDDatabase.h>
#import "TDRouter.h"
#import "TDReplicator.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"
#import "MYURLUtils.h"


// Max number of retry attempts for a transient failure, and the backoff time formula
#define kMaxRetries 2
#define RetryDelay(COUNT) (4 << (COUNT))        // COUNT starts at 0


@implementation TDRemoteRequest


+ (NSString*) userAgentHeader {
    return $sprintf(@"TouchDB/%@", [TDRouter versionString]);
}


- (id) initWithMethod: (NSString*)method 
                  URL: (NSURL*)url 
                 body: (id)body
       requestHeaders: (NSDictionary *)requestHeaders
         onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    self = [super init];
    if (self) {
        _onCompletion = [onCompletion copy];
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;
        _request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        // Add headers.
        [_request setValue: [[self class] userAgentHeader] forHTTPHeaderField:@"User-Agent"];
        [requestHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [_request setValue:value forHTTPHeaderField:key];
        }];
        
        [self setupRequest: _request withBody: body];

    }
    return self;
}


- (id<TDAuthorizer>) authorizer {
    return _authorizer;
}

- (void) setAuthorizer: (id<TDAuthorizer>)authorizer {
    if (ifSetObj(&_authorizer, authorizer)) {
        [_request setValue: [authorizer authorizeURLRequest: _request forRealm: nil]
                  forHTTPHeaderField: @"Authorization"];
    }
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    // subclasses can override this.
}


- (void) dontLog404 {
    _dontLog404 = true;
}


- (void) start {
    if (!_request)
        return;     // -clearConnection already called
    LogTo(RemoteRequest, @"%@: Starting...", self);
    Assert(!_connection);
    _connection = [[NSURLConnection connectionWithRequest: _request delegate: self] retain];
    // Retaining myself shouldn't be necessary, because NSURLConnection is documented as retaining
    // its delegate while it's running. But GNUstep doesn't (currently) do this, so for
    // compatibility I retain myself until the connection completes (see -clearConnection.)
    // TODO: Remove this and the [self autorelease] below when I get the fix from GNUstep.
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
    [_authorizer release];
    [super dealloc];
}


- (NSString*) description {
    return $sprintf(@"%@[%@ %@]", [self class], _request.HTTPMethod, _request.URL);
}


- (NSMutableDictionary*) statusInfo {
    return $mdict({@"URL", _request.URL.absoluteString}, {@"method", _request.HTTPMethod});
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    Assert(result || error);
    _onCompletion(result, error);
}


- (void) startAfterDelay: (NSTimeInterval)delay {
    // assumes _connection already failed or canceled.
    [_connection autorelease];
    _connection = nil;
    [self performSelector: @selector(start) withObject: nil afterDelay: delay];
}


- (void) stop {
    if (_connection) {
        LogTo(RemoteRequest, @"%@: Stopped", self);
        [_connection cancel];
    }
    [self clearConnection];
    if (_onCompletion) {
        NSError* error = [NSError errorWithDomain: NSURLErrorDomain code: NSURLErrorCancelled
                                         userInfo: nil];
        [self respondWithResult: nil error: error];
        [_onCompletion release];   // break cycles
        _onCompletion = nil;
    }
}


- (void) cancelWithStatus: (int)status {
    [_connection cancel];
    [self connection: _connection didFailWithError: TDStatusToNSError(status, _request.URL)];
}


- (BOOL) retry {
    // Note: This assumes all requests are idempotent, since even though we got an error back, the
    // request might have succeeded on the remote server, and by retrying we'd be issuing it again.
    // PUT and POST requests aren't generally idempotent, but the ones sent by the replicator are.
    
    if (_retryCount >= kMaxRetries)
        return NO;
    NSTimeInterval delay = RetryDelay(_retryCount);
    ++_retryCount;
    LogTo(RemoteRequest, @"%@: Will retry in %g sec", self, delay);
    [self startAfterDelay: delay];
    return YES;
}


- (bool) retryWithCredential {
    if (_authorizer || _challenged)
        return false;
    _challenged = YES;
    NSURLCredential* cred = [_request.URL my_credentialForRealm: nil
                                           authenticationMethod: NSURLAuthenticationMethodHTTPBasic];
    if (!cred) {
        LogTo(RemoteRequest, @"Got 401 but no stored credential found (with nil realm)");
        return false;
    }

    [_connection cancel];
    self.authorizer = [[[TDBasicAuthorizer alloc] initWithCredential: cred] autorelease];
    LogTo(RemoteRequest, @"%@ retrying with %@", self, _authorizer);
    [self startAfterDelay: 0.0];
    return true;
}


#pragma mark - NSURLCONNECTION DELEGATE:


- (void)connection:(NSURLConnection *)connection
        willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    id<NSURLAuthenticationChallengeSender> sender = challenge.sender;
    NSURLProtectionSpace* space = challenge.protectionSpace;
    NSString* authMethod = space.authenticationMethod;
    LogTo(RemoteRequest, @"Got challenge: %@ (%@)", challenge, authMethod);
    if ($equal(authMethod, NSURLAuthenticationMethodHTTPBasic)) {
        _challenged = true;
        if (challenge.previousFailureCount == 0) {
            NSURLCredential* cred = [_request.URL my_credentialForRealm: space.realm
                                                   authenticationMethod: authMethod];
            if (cred) {
                [sender useCredential: cred forAuthenticationChallenge:challenge];
                return;
            }
        }
    } else if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
        SecTrustRef trust = space.serverTrust;
        if ([[self class] checkTrust: trust forHost: space.host]) {
            [sender useCredential: [NSURLCredential credentialForTrust: trust]
                    forAuthenticationChallenge: challenge];
        } else {
            [sender cancelAuthenticationChallenge: challenge];
        }
    }
    [sender performDefaultHandlingForAuthenticationChallenge: challenge];
}


+ (BOOL) checkTrust: (SecTrustRef)trust forHost: (NSString*)host {
    SecTrustResultType trustResult;
    OSStatus err = SecTrustEvaluate(trust, &trustResult);
    if (err == noErr && (trustResult == kSecTrustResultProceed ||
                         trustResult == kSecTrustResultUnspecified)) {
        return YES;
    } else {
        Warn(@"TouchDB: SSL server <%@> not trusted (err=%d, trustResult=%u); cert chain follows:",
             host, (int)err, (unsigned)trustResult);
#if TARGET_OS_IPHONE
        for (CFIndex i = 0; i < SecTrustGetCertificateCount(trust); ++i) {
            SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, i);
            CFStringRef subject = SecCertificateCopySubjectSummary(cert);
            Warn(@"    %@", subject);
            CFRelease(subject);
        }
#else
        NSArray* trustProperties = NSMakeCollectable(SecTrustCopyProperties(trust));
        for (NSDictionary* property in trustProperties) {
            Warn(@"    %@: error = %@",
                 property[(id)kSecPropertyTypeTitle],
                 property[(id)kSecPropertyTypeError]);
        }
        [trustProperties release];
#endif
        return NO;
    }

}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _status = (int) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(RemoteRequest, @"%@: Got response, status %d", self, _status);
    if (_status == 401) {
        // CouchDB says we're unauthorized but it didn't present a 'WWW-Authenticate' header
        // (it actually does this on purpose...) Let's see if we have a credential we can try:
        if ([self retryWithCredential])
            return;
    }
    if (TDStatusIsError(_status)) 
        [self cancelWithStatus: _status];
}


- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response
{
    // The redirected request needs to be authorized again:
    if (![request valueForHTTPHeaderField: @"Authorization"]) {
        NSMutableURLRequest* nuRequest = [[request mutableCopy] autorelease];
        NSString* auth;
        if (_authorizer)
            auth = [_authorizer authorizeURLRequest: nuRequest forRealm: nil];
        else
            auth = [_request valueForHTTPHeaderField: @"Authorization"];
        [nuRequest setValue: auth forHTTPHeaderField: @"Authorization"];
        request = nuRequest;
    }
    return request;
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(RemoteRequest, @"%@: Got %lu bytes", self, (unsigned long)data.length);
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (WillLog()) {
        if (!(_dontLog404 && error.code == kTDStatusNotFound && $equal(error.domain, TDHTTPErrorDomain)))
            Log(@"%@: Got error %@", self, error);
    }
    
    // If the error is likely transient, retry:
    if (TDMayBeTransientError(error) && [self retry])
        return;
    
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
    NSError* error = nil;
    if (_jsonBuffer.length > 0) {
        result = [TDJSON JSONObjectWithData: _jsonBuffer options: 0 error: NULL];
        if (!result) {
            Warn(@"%@: %@ %@ returned unparseable data '%@'",
                 self, _request.HTTPMethod, _request.URL, [_jsonBuffer my_UTF8ToString]);
            error = TDStatusToNSError(kTDStatusUpstreamError, _request.URL);
        }
    } else {
        result = $dict();
    }
    [self clearConnection];
    [self respondWithResult: result error: error];
}

@end
