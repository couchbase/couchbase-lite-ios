//
//  CBLRemoteRequest.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/15/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLRemoteRequest.h"
#import "CBLAuthorizer.h"
#import "CBLClientCertAuthorizer.h"
#import "CBLMisc.h"
#import "CBLStatus.h"
#import "CBL_BlobStore.h"
#import "CBLDatabase.h"
#import "CBLRestReplicator.h"
#import "CollectionUtils.h"
#import "Logging.h"
#import "Test.h"
#import "MYURLUtils.h"
#import "CBLGZip.h"
#import "CBLCookieStorage.h"


// Max number of retry attempts for a transient failure, and the backoff time formula
#define kMaxRetries 2
#define RetryDelay(COUNT) (4 << (COUNT))        // COUNT starts at 0


typedef enum {
    kNoAuthChallenge,
    kTryAuthorizer,
    kTryProposed,
    kFindCredential,
    kGiveUp
} AuthPhase;


@implementation CBLRemoteRequest
{
    AuthPhase _authPhase;
    NSURLCredential* _proposedCredential;
}


@synthesize delegate=_delegate, responseHeaders=_responseHeaders, cookieStorage=_cookieStorage;
@synthesize autoRetry = _autoRetry;
#if DEBUG
@synthesize debugAlwaysTrust=_debugAlwaysTrust;
#endif


- (instancetype) initWithMethod: (NSString*)method
                            URL: (NSURL*)url
                           body: (id)body
                 requestHeaders: (NSDictionary *)requestHeaders
                   onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    self = [super init];
    if (self) {
        _onCompletion = [onCompletion copy];
        _autoRetry = YES;
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;
        _request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        
        // Add headers.
        [_request setValue: [CBL_ReplicatorSettings userAgentHeader] forHTTPHeaderField:@"User-Agent"];
        [requestHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [_request setValue:value forHTTPHeaderField:key];
            // If app explicitly wants to set a cookie, we have to stop NSURLRequest from using its
            // default cookie handling, else it overwrites "Cookie:" header with its own. (#532)
            if ([key caseInsensitiveCompare: @"Cookie"] == 0)
                _request.HTTPShouldHandleCookies = NO;
        }];

        [self setupRequest: _request withBody: body];

    }
    return self;
}


- (NSTimeInterval) timeoutInterval {
    return _request.timeoutInterval;
}

- (void) setTimeoutInterval:(NSTimeInterval)timeout {
    _request.timeoutInterval = timeout;
}


- (id<CBLAuthorizer>) authorizer {
    return _authorizer;
}

- (void) setAuthorizer: (id<CBLAuthorizer>)authorizer {
    if (_authorizer != authorizer) {
        _authorizer = authorizer;
        [$castIfProtocol(CBLCustomHeadersAuthorizer, _authorizer) authorizeURLRequest: _request];
    }
}

- (void) setCookieStorage:(CBLCookieStorage *)cookieStorage {
    if (_cookieStorage != cookieStorage) {
        _cookieStorage = cookieStorage;
        if (_request.HTTPShouldHandleCookies) {
            [_cookieStorage addCookieHeaderToRequest: _request];
        }
    }
}


- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    // subclasses can override this.
}


- (BOOL) compressBody {
    NSData* body = _request.HTTPBody;
    if (body.length < 100 || [_request valueForHTTPHeaderField: @"Content-Encoding"] != nil)
        return NO;
    NSData* encoded = [CBLGZip dataByCompressingData: body];
    if (encoded.length >= body.length)
        return NO;
    _request.HTTPBody = encoded;
    [_request setValue: @"gzip" forHTTPHeaderField: @"Content-Encoding"];
    return YES;
}


- (void) dontLog404 {
    _dontLog404 = true;
}


- (void) start {
    if (!_request)
        return;     // -clearConnection already called
    _responseHeaders = nil;
    _authPhase = kNoAuthChallenge;
    LogTo(RemoteRequest, @"%@: Starting...", self);
    Assert(!_connection);
    _connection = [NSURLConnection connectionWithRequest: _request delegate: self];
}


- (void) clearConnection {
    _request = nil;
    _connection = nil;
}


- (void)dealloc {
    [self clearConnection];
}


- (NSString*) description {
    return $sprintf(@"%@[%@ %@]",
                    [self class], _request.HTTPMethod, _request.URL.my_sanitizedString);
}


- (NSMutableDictionary*) statusInfo {
    return $mdict({@"URL", _request.URL.absoluteString}, {@"method", _request.HTTPMethod});
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    Assert(result || error);
    _onCompletion(result, error);
    _onCompletion = nil;  // break cycles
}


- (void) startAfterDelay: (NSTimeInterval)delay {
    // assumes _connection already failed or canceled.
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
        _onCompletion = nil;  // break cycles
    }
}


- (void) cancelWithStatus: (int)status {
    if (!_connection)
        return;
    [_connection cancel];
    [self connection: _connection
          didFailWithError: CBLStatusToNSErrorWithInfo(status, nil, _request.URL, nil)];
}


- (BOOL) retry {
    // Note: This assumes all requests are idempotent, since even though we got an error back, the
    // request might have succeeded on the remote server, and by retrying we'd be issuing it again.
    // PUT and POST requests aren't generally idempotent, but the ones sent by the replicator are.
    if (!_autoRetry || _retryCount >= kMaxRetries)
        return NO;
    NSTimeInterval delay = RetryDelay(_retryCount);
    ++_retryCount;
    LogTo(RemoteRequest, @"%@: Will retry in %g sec", self, delay);
    [self startAfterDelay: delay];
    return YES;
}


- (bool) retryWithCredential {
    if (!_autoRetry || _authorizer || _challenged)
        return false;
    _challenged = true;
    CBLPasswordAuthorizer *auth = [[CBLPasswordAuthorizer alloc] initWithURL: _request.URL];
    if (!auth) {
        LogTo(RemoteRequest, @"Got 401 but no stored credential found (with nil realm)");
        return false;
    }

    [_connection cancel];
    self.authorizer = auth;
    LogTo(RemoteRequest, @"%@ retrying with %@", self, auth);
    [self startAfterDelay: 0.0];
    return true;
}


- (NSURLCredential*) nextCredentialToTry: (NSURLAuthenticationChallenge*)challenge {
    NSURLCredential* cred;
    do {
        switch (++_authPhase) {
            case kTryAuthorizer:
                _proposedCredential = challenge.proposedCredential;
                cred = $castIf(CBLPasswordAuthorizer, _authorizer).credential;
                break;
            case kTryProposed:
                cred = _proposedCredential;
                _proposedCredential = nil;
                break;
            case kFindCredential: {
                NSURLProtectionSpace* space = challenge.protectionSpace;
                cred = [_request.URL my_credentialForRealm: space.realm
                                      authenticationMethod: space.authenticationMethod];
                break;
            }
            default:
                return nil; // give up
        }
    } while (cred == nil || (cred.user && !cred.hasPassword));
    return cred;
}


#pragma mark - NSURLCONNECTION DELEGATE:


void CBLWarnUntrustedCert(NSString* host, SecTrustRef trust) {
    Warn(@"CouchbaseLite: SSL server <%@> not trusted; cert chain follows:", host);
#if TARGET_OS_IPHONE
    for (CFIndex i = 0; i < SecTrustGetCertificateCount(trust); ++i) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, i);
        CFStringRef subject = SecCertificateCopySubjectSummary(cert);
        Warn(@"    %@", subject);
        CFRelease(subject);
    }
#else
#ifdef __OBJC_GC__
    NSArray* trustProperties = NSMakeCollectable(SecTrustCopyProperties(trust));
#else
    NSArray* trustProperties = (__bridge_transfer NSArray *)SecTrustCopyProperties(trust);
#endif
    for (NSDictionary* property in trustProperties) {
        Warn(@"    %@: error = %@",
             property[(__bridge id)kSecPropertyTypeTitle],
             property[(__bridge id)kSecPropertyTypeError]);
    }
#endif
}


- (void)connection:(NSURLConnection *)connection
        willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    id<NSURLAuthenticationChallengeSender> sender = challenge.sender;
    NSURLProtectionSpace* space = challenge.protectionSpace;
    NSString* authMethod = space.authenticationMethod;
    LogTo(RemoteRequest, @"Got challenge for %@: method=%@, proposed=%@, err=%@", self, authMethod, challenge.proposedCredential, challenge.error);
    if ($equal(authMethod, NSURLAuthenticationMethodHTTPBasic) ||
            $equal(authMethod, NSURLAuthenticationMethodHTTPDigest)) {
        _challenged = true;
        NSURLCredential* cred = [self nextCredentialToTry: challenge];
        if (cred) {
            LogTo(RemoteRequest, @"    challenge: (phase %d) useCredential: %@", _authPhase, cred);
            [sender useCredential: cred forAuthenticationChallenge:challenge];
            // Update my authorizer so my owner (the replicator) can pick it up when I'm done
            if (_authPhase > kTryAuthorizer)
                _authorizer = [[CBLPasswordAuthorizer alloc] initWithCredential: cred];
            return;
        } else {
            _authorizer = nil;
            LogTo(RemoteRequest, @"    challenge: (phase %d) continueWithoutCredential", _authPhase);
            [sender continueWithoutCredentialForAuthenticationChallenge: challenge];
        }

    } else if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
        // Verify the _server's_ SSL certificate:
        SecTrustRef trust = space.serverTrust;
        BOOL ok;
        if (_delegate)
            ok = [_delegate checkSSLServerTrust: space];
        else {
            SecTrustResultType result;
            ok = (SecTrustEvaluate(trust, &result) == noErr) &&
                    (result==kSecTrustResultProceed || result==kSecTrustResultUnspecified);
#if DEBUG
            if (!ok && _debugAlwaysTrust) {
                ok = YES;
                CFDataRef exception = SecTrustCopyExceptions(trust);
                if (exception) {
                    SecTrustSetExceptions(trust, exception);
                    CFRelease(exception);
                }
            }
#endif
        }
        if (ok) {
            LogTo(RemoteRequest, @"    useCredential for trust: %@", trust);
            [sender useCredential: [NSURLCredential credentialForTrust: trust]
                    forAuthenticationChallenge: challenge];
        } else {
            CBLWarnUntrustedCert(space.host, trust);
            LogTo(RemoteRequest, @"    challenge: fail (untrusted cert)");
            [sender continueWithoutCredentialForAuthenticationChallenge: challenge];
        }

    } else if ($equal(authMethod, NSURLAuthenticationMethodClientCertificate)) {
        // Request for SSL client cert:
        if (challenge.previousFailureCount == 0) {
            NSURLCredential* cred = $castIf(CBLClientCertAuthorizer, _authorizer).credential;
            if (cred) {
                LogTo(RemoteRequest, @"    challenge: sending SSL client cert");
                [sender useCredential: cred forAuthenticationChallenge:challenge];
                return;
            }
            LogTo(RemoteRequest, @"    challenge: no SSL client cert");
        } else {
            _authorizer = nil;
            LogTo(RemoteRequest, @"    challenge: SSL client cert rejected");
        }
        [sender continueWithoutCredentialForAuthenticationChallenge: challenge];
        
    } else {
        LogTo(RemoteRequest, @"    challenge: performDefaultHandling");
        [sender performDefaultHandlingForAuthenticationChallenge: challenge];
    }
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _status = (int) ((NSHTTPURLResponse*)response).statusCode;
    _responseHeaders = ((NSHTTPURLResponse*)response).allHeaderFields;

    if (_cookieStorage)
        [_cookieStorage setCookieFromResponse: (NSHTTPURLResponse*)response];

    LogTo(RemoteRequest, @"%@: Got response, status %d", self, _status);
    if (_status == 401) {
        // CouchDB says we're unauthorized but it didn't present a 'WWW-Authenticate' header
        // (it actually does this on purpose...) Let's see if we have a credential we can try:
        if ([self retryWithCredential])
            return;
    }

#if DEBUG
    if (!CBLStatusIsError(_status)) {
        // By setting the user default "CBLFakeFailureRate" to a number between 0.0 and 1.0,
        // you can artificially cause failures of that fraction of requests, for testing.
        // The status will be 567, or the value of "CBLFakeFailureStatus" if it's set.
        NSUserDefaults* dflts = [NSUserDefaults standardUserDefaults];
        float fakeFailureRate = [dflts floatForKey: @"CBLFakeFailureRate"];
        if (fakeFailureRate > 0.0 && random() < fakeFailureRate * 0x7FFFFFFF) {
            AlwaysLog(@"***FAKE FAILURE: %@", self);
            _status = (int)[dflts integerForKey: @"CBLFakeFailureStatus"] ?: 567;
        }
    }
#endif
    
    if (CBLStatusIsError(_status))
        [self cancelWithStatus: _status];
}


- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response
{
    // The redirected request needs to be authorized again:
    if (![request valueForHTTPHeaderField: @"Authorization"]) {
        NSMutableURLRequest* nuRequest = [request mutableCopy];
        id<CBLCustomHeadersAuthorizer> customAuth = $castIfProtocol(CBLCustomHeadersAuthorizer, _authorizer);
        if (customAuth) {
            [customAuth authorizeURLRequest: nuRequest];
        } else {
            NSString* authHeader = [_request valueForHTTPHeaderField: @"Authorization"];
            [nuRequest setValue: authHeader forHTTPHeaderField: @"Authorization"];
        }
        request = nuRequest;
    }
    return request;
}


- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(RemoteRequestVerbose, @"%@: Got %lu bytes", self, (unsigned long)data.length);
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (WillLog()) {
        if (!(_dontLog404 && error.code == kCBLStatusNotFound && $equal(error.domain, CBLHTTPErrorDomain)))
            Log(@"%@: Got error %@", self, error);
    }
    
    // If the error is likely transient, retry:
    if (CBLMayBeTransientError(error) && [self retry])
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




@implementation CBLRemoteJSONRequest

- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    [request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    if (body) {
        request.HTTPBody = [CBLJSON dataWithJSONObject: body options: 0 error: NULL];
        [request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
    }
}

- (void) clearConnection {
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
        result = [CBLJSON JSONObjectWithData: _jsonBuffer options: 0 error: NULL];
        if (!result) {
            Warn(@"%@: %@ %@ returned unparseable data '%@'",
                 self, _request.HTTPMethod, _request.URL, [_jsonBuffer my_UTF8ToString]);
            error = CBLStatusToNSErrorWithInfo(kCBLStatusUpstreamError, nil, _request.URL, nil);
        }
    } else {
        result = $dict();
    }
    [self clearConnection];
    [self respondWithResult: result error: error];
}

@end
