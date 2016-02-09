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
#import "CBLRemoteSession.h"
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
@synthesize autoRetry = _autoRetry, dontStop=_dontStop, session=_session, task=_task;
#if DEBUG
@synthesize debugAlwaysTrust=_debugAlwaysTrust;
#endif


- (instancetype) initWithMethod: (NSString*)method
                            URL: (NSURL*)url
                           body: (id)body
                   onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    self = [super init];
    if (self) {
        _onCompletion = [onCompletion copy];
        _autoRetry = YES;
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;
        _request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

        // Interpret non-NSData body as a JSON object:
        if (body) {
            if (![body isKindOfClass: [NSData class]]) {
                NSError* error;
                body = [CBLJSON dataWithJSONObject: body options:0 error: &error];
                Assert(body, @"Cannot encode JSON body: %@", error);
                [_request addValue: @"application/json" forHTTPHeaderField: @"Content-Type"];
            }
            _request.HTTPBody = body;
        }
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
        [_cookieStorage addCookieHeaderToRequest: _request];
    }
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


- (NSURLSessionTask*) createTaskInURLSession: (NSURLSession*)session {
    if (!_request)
        return nil;     // -clearConnection already called
    _responseHeaders = nil;
    _authPhase = kNoAuthChallenge;
    LogTo(RemoteRequest, @"%@: Starting...", self);
    Assert(!_task);
    _task = [session dataTaskWithRequest: _request];
    return _task;
}


- (void) clearConnection {
    _request = nil;
    _task = nil;
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


- (BOOL) running {
    return _task != nil;
}


- (void) respondWithResult: (id)result error: (NSError*)error {
    Assert(result || error);

    CBLRemoteRequestCompletionBlock onCompletion = _onCompletion;   // keep block alive till return
    onCompletion(result, error);
    _onCompletion = nil;  // break cycles
}


- (void) startAfterDelay: (NSTimeInterval)delay {
    // assumes _task already failed or canceled.
    _task = nil;
    CBLRemoteSession* session = _session;
    Assert(session);
    [session performSelector: @selector(startRequest:) withObject: self afterDelay: delay];
}


- (void) stop {
    if (_dontStop)
        return;
    if (_task) {
        LogTo(RemoteRequest, @"%@: Stopped", self);
        [_task cancel];
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
    if (!_task)
        return;
    [_task cancel];
    [self didFailWithError: CBLStatusToNSErrorWithInfo(status, nil, _request.URL, nil)];
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

    [_task cancel];
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


#pragma mark - AUTHENTICATION


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


- (NSURLSessionAuthChallengeDisposition)
                                    didReceiveChallenge:(NSURLAuthenticationChallenge*)challenge
                                          useCredential: (NSURLCredential**)outCredential
{
    *outCredential = nil;

    NSURLProtectionSpace* space = challenge.protectionSpace;
    NSString* authMethod = space.authenticationMethod;
    LogTo(RemoteRequest, @"Got challenge for %@: method=%@, proposed=%@, err=%@", self, authMethod, challenge.proposedCredential, challenge.error);
    if ($equal(authMethod, NSURLAuthenticationMethodHTTPBasic) ||
            $equal(authMethod, NSURLAuthenticationMethodHTTPDigest)) {
        _challenged = true;
        *outCredential = [self nextCredentialToTry: challenge];
        if (*outCredential) {
            LogTo(RemoteRequest, @"    challenge: (phase %d) useCredential: %@",
                  _authPhase, *outCredential);
            // Update my authorizer so my owner (the replicator) can pick it up when I'm done
            if (_authPhase > kTryAuthorizer)
                _authorizer = [[CBLPasswordAuthorizer alloc] initWithCredential: *outCredential];
        } else {
            _authorizer = nil;
            LogTo(RemoteRequest, @"    challenge: (phase %d) continueWithoutCredential", _authPhase);
        }
        return NSURLSessionAuthChallengeUseCredential;

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
            *outCredential = [NSURLCredential credentialForTrust: trust];
        } else {
            CBLWarnUntrustedCert(space.host, trust);
            LogTo(RemoteRequest, @"    challenge: fail (untrusted cert)");
        }
        return NSURLSessionAuthChallengeUseCredential;

    } else if ($equal(authMethod, NSURLAuthenticationMethodClientCertificate)) {
        // Request for SSL client cert:
        if (challenge.previousFailureCount == 0) {
            *outCredential = $castIf(CBLClientCertAuthorizer, _authorizer).credential;
            if (*outCredential)
                LogTo(RemoteRequest, @"    challenge: sending SSL client cert");
            else
                LogTo(RemoteRequest, @"    challenge: no SSL client cert");
        } else {
            _authorizer = nil;
            LogTo(RemoteRequest, @"    challenge: SSL client cert rejected");
        }
        return NSURLSessionAuthChallengeUseCredential;

    } else {
        LogTo(RemoteRequest, @"    challenge: performDefaultHandling");
        return NSURLSessionAuthChallengePerformDefaultHandling;
    }
}


- (NSURLRequest*) willSendRequest:(NSURLRequest *)request
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


#pragma mark CALLBACKS:


- (NSInputStream *) needNewBodyStream {
    Warn(@"Unexpected call to needNewBodyStream");
    return nil;
}


- (void) didReceiveResponse:(NSHTTPURLResponse *)response {
    _status = (int) response.statusCode;
    _responseHeaders = response.allHeaderFields;

    if (_cookieStorage)
        [_cookieStorage setCookieFromResponse: response];

    [_delegate remoteRequestReceivedResponse: self];

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


- (void) didReceiveData:(NSData *)data {
//    LogTo(RemoteRequestVerbose, @"%@: Got %lu bytes", self, (unsigned long)data.length);
}


- (void) didFailWithError:(NSError *)error {
    if (error && !_request)
        return;     // This is an echo of my canceling the task

    if (WillLog()) {
        if (!(_dontLog404 && error.code == kCBLStatusNotFound && $equal(error.domain, CBLHTTPErrorDomain)))
            Log(@"%@: Got error %@", self, error);
    }

    [_task cancel];
    _task = nil;

    // If the error is likely transient, retry:
    if (CBLMayBeTransientError(error) && [self retry])
        return;
    
    [self clearConnection];
    [self respondWithResult: nil error: error];
}


- (void)didFinishLoading {
    LogTo(RemoteRequest, @"%@: Finished loading", self);
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


@end




@implementation CBLRemoteJSONRequest

- (instancetype) initWithMethod: (NSString*)method
                            URL: (NSURL*)url
                           body: (id)body
                   onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion
{
    self = [super initWithMethod: method
                             URL: url
                            body: body
                    onCompletion: onCompletion];
    if (self) {
        [_request setValue: @"application/json" forHTTPHeaderField: @"Accept"];
    }
    return self;
}

- (void) clearConnection {
    _jsonBuffer = nil;
    [super clearConnection];
}

- (void) didReceiveData:(NSData *)data {
    [super didReceiveData: data];
    if (!_jsonBuffer)
        _jsonBuffer = [[NSMutableData alloc] initWithCapacity: MAX(data.length, 8192u)];
    [_jsonBuffer appendData: data];
}

- (void) didFinishLoading {
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
