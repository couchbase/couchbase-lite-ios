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
#import "CBLGZip.h"
#import "CBLCookieStorage.h"
#import "BLIPHTTPLogic.h"
#import "MYURLUtils.h"


DefineLogDomain(RemoteRequest);


// Max number of retry attempts for a transient failure, and the backoff time formula
#define kMaxRetries 2
#define RetryDelay(COUNT) (4 << (COUNT))        // COUNT starts at 0


typedef enum {
    kNoAuthChallenge,
    kTryAuthorizer,
    kFindCredential,
    kGiveUp
} AuthPhase;


@implementation CBLRemoteRequest
{
    BOOL _followRedirects;
    AuthPhase _authPhase;
    NSMutableData* _jsonBuffer;
}


@synthesize delegate=_delegate, responseHeaders=_responseHeaders, cookieStorage=_cookieStorage;
@synthesize autoRetry = _autoRetry, dontStop=_dontStop, session=_session, task=_task;
#if DEBUG
@synthesize URLRequest=_request, onCompletion=_onCompletion;
@synthesize statusCode=_status, debugAlwaysTrust=_debugAlwaysTrust;
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
        _followRedirects = YES;
        _request = [[NSMutableURLRequest alloc] initWithURL: url];
        _request.HTTPMethod = method;

        // Interpret non-NSData body as a JSON object:
        if (body) {
            if (![body isKindOfClass: [NSData class]]) {
                NSError* error;
                body = [CBLJSON dataWithJSONObject: body options:0 error: &error];
                Assert(body, @"Cannot encode JSON body: %@", error.my_compactDescription);
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
        // Let the authorizer add an Authorization: header if it wants:
        id<CBLCustomHeadersAuthorizer> a = $castIfProtocol(CBLCustomHeadersAuthorizer, _authorizer);
        if ([a authorizeURLRequest: _request])
            LogTo(RemoteRequest, @"Added Authorization header for %@", a);
    }
}

- (void) setCookieStorage:(CBLCookieStorage *)cookieStorage {
    if (_cookieStorage != cookieStorage) {
        _cookieStorage = cookieStorage;
        // Let the cookie storage add a Cookie: header, unless the app has specified its own cookes:
        if (![_request valueForHTTPHeaderField: @"Cookie"])
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
- (void) dontRedirect {
    _followRedirects = NO;
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
    _jsonBuffer = nil;
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
    if (onCompletion) {
        _onCompletion = nil;  // break cycles
        onCompletion(result, error);
    }
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


- (void) cancelWithStatus: (int)status message: (NSString*)message {
    if (!_task)
        return;
    [_task cancel];
    [self didFailWithStatus: status message: message extra: nil];
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


#pragma mark - AUTHENTICATION


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
    NSURLCredential* cred = nil;
    do {
        switch (++_authPhase) {
            case kTryAuthorizer:
                // If _authorizer hasn't already been tried (by adding its Authorization header),
                // try it first:
                if ([_request valueForHTTPHeaderField: @"Authorization"] == nil)
                    cred = $castIf(CBLPasswordAuthorizer, _authorizer).credential;
                break;
            case kFindCredential: {
                // 2nd attempt: Look up a credential, either one embedded in the URL or one found
                // in the credential store:
                NSURLProtectionSpace* space = challenge.protectionSpace;
                cred = [_request.URL my_credentialForRealm: space.realm
                                      authenticationMethod: space.authenticationMethod];
                break;
            }
            default:
                // 3rd: Give up
                return nil;
        }
    } while (cred == nil || (cred.user && !cred.hasPassword));
    return cred;
}


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
    for (NSDictionary* property in CFBridgingRelease(SecTrustCopyProperties(trust))) {
        Warn(@"    %@: error = %@",
             property[(__bridge id)kSecPropertyTypeTitle],
             property[(__bridge id)kSecPropertyTypeError]);
    }
#endif
}


- (NSURLCredential*) credentialForHTTPAuthChallenge: (NSURLAuthenticationChallenge*)challenge
                                disposition: (NSURLSessionAuthChallengeDisposition*)outDisposition
{
    _challenged = true;
    NSURLCredential* cred = [self nextCredentialToTry: challenge];
    if (cred) {
        LogTo(RemoteRequest, @"    challenge: (phase %d) useCredential: %@, persistence=%lu",
              _authPhase, cred, (unsigned long)(cred).persistence);
        // Update my authorizer so the CBLRemoteSession can pick it up on success
        if (_authPhase > kTryAuthorizer)
            _authorizer = [[CBLPasswordAuthorizer alloc] initWithCredential: cred];
        *outDisposition = NSURLSessionAuthChallengeUseCredential;
    } else {
        _authorizer = nil;
        LogTo(RemoteRequest, @"    challenge: (phase %d) continueWithoutCredential", _authPhase);
    }
    return cred;
}


- (NSURLCredential*) credentialForClientCertChallenge: (NSURLAuthenticationChallenge*)challenge
                                disposition: (NSURLSessionAuthChallengeDisposition*)outDisposition
{
    NSURLCredential* cred = nil;
    if (challenge.previousFailureCount == 0) {
        cred = $castIf(CBLClientCertAuthorizer, _authorizer).credential;
        if (cred) {
            LogTo(RemoteRequest, @"    challenge: sending SSL client cert");
            *outDisposition = NSURLSessionAuthChallengeUseCredential;
        } else {
            LogTo(RemoteRequest, @"    challenge: no SSL client cert");
        }
    } else {
        _authorizer = nil;
        LogTo(RemoteRequest, @"    challenge: SSL client cert rejected");
    }
    return cred;
}


- (SecTrustRef) checkServerTrust:(NSURLAuthenticationChallenge*)challenge {
    NSURLProtectionSpace* space = challenge.protectionSpace;
    SecTrustRef trust = space.serverTrust;
    BOOL ok;
    id<CBLRemoteRequestDelegate> _strongDelegate = _delegate;
    if (_strongDelegate) {
        ok = [_strongDelegate checkSSLServerTrust: space];
    }else {
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
        return trust;
    } else {
        CBLWarnUntrustedCert(space.host, trust);
        LogTo(RemoteRequest, @"    challenge: fail (untrusted cert)");
        return NULL;
    }
}


#pragma mark - CALLBACKS:


- (NSURLRequest*) willSendRequest:(NSURLRequest *)request
                 redirectResponse:(NSHTTPURLResponse *)response
{
    if (!_followRedirects) {
        //??[self didReceiveResponse: response];
        return nil;
    }
    LogTo(RemoteRequest, @"%@ redirected to <%@>", self, request.URL.absoluteString);
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
            Log(@"***FAKE FAILURE: %@", self);
            _status = (int)[dflts integerForKey: @"CBLFakeFailureStatus"] ?: 567;
        }
    }
#endif
    
    if (CBLStatusIsError(_status)) {
        if (errorResponseMayBeJSON(response)) {
            // Wait to receive the response before signaling an error, so we can read the error
            // message/reason out of the JSON.
            _jsonBuffer = [NSMutableData new];
        } else {
            [self cancelWithStatus: _status
                           message: [NSHTTPURLResponse localizedStringForStatusCode: _status]];
        }
    }
}


// CBLRemoteSession calls this
- (void) _didReceiveData:(NSData *)data {
    LogVerbose(RemoteRequest, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    if (CBLStatusIsError(_status)) {
        [self appendJSON: data];
    } else {
        [self didReceiveData: data];
    }
}

// subclasses override this
- (void) didReceiveData:(NSData *)data {
}


- (void) appendJSON:(NSData *)data {
    if (!_jsonBuffer)
        _jsonBuffer = [[NSMutableData alloc] initWithCapacity: MAX(data.length, 8192u)];
    [_jsonBuffer appendData: data];
}

- (id) parseJSONResponse: (NSError**)outError {
    if (!_jsonBuffer) {
        if (outError) *outError = nil;
        return nil;
    }
    NSError* parseError;
    id result = [CBLJSON JSONObjectWithData: _jsonBuffer options: 0 error: &parseError];
    if (!result && outError) {
        Warn(@"%@: %@ %@ returned unparseable data '%@'",
             self, _request.HTTPMethod, _request.URL, [_jsonBuffer my_UTF8ToString]);
        *outError = CBLStatusToNSErrorWithInfo(kCBLStatusUpstreamError, nil, _request.URL,
                                               @{NSUnderlyingErrorKey: parseError});
    }
    _jsonBuffer = nil;
    return result;
}


- (void) didFailWithError:(NSError *)error {
    if (error && !_request)
        return;     // This is an echo of my canceling the task

    if (WillLog()) {
        if (!(_dontLog404 && error.code == kCBLStatusNotFound && $equal(error.domain, CBLHTTPErrorDomain)))
            Log(@"%@: Got error %@", self, error.my_compactDescription);
    }

    [_task cancel];
    _task = nil;

    // If the error is likely transient, retry:
    if (CBLMayBeTransientError(error) && [self retry])
        return;
    
    [self clearConnection];
    [self respondWithResult: nil error: error];
}

- (void) didFailWithStatus: (CBLStatus)status
                   message: (NSString*)message
                     extra: (NSMutableDictionary*)extra
{
    if (status == 401 || status == 407) {
        NSDictionary* challenge = [BLIPHTTPLogic parseAuthHeader: _responseHeaders[@"WWW-Authenticate"]];
        if (challenge) {
            if (!extra)
                extra = $mdict();
            extra[@"AuthChallenge"] = challenge;
        }
    }
    [self didFailWithError: CBLStatusToNSErrorWithInfo(status, message, _request.URL, extra)];
}


// CBLRemoteSession calls this
- (void) _didFinishLoading {
    if (CBLStatusIsError(_status) && _jsonBuffer) {
        // Response has an error status, and we were waiting to get the JSON message:
        LogTo(RemoteRequest, @"%@: JSON error message is: %@", self, _jsonBuffer.my_UTF8ToString);
        NSDictionary* info = $castIf(NSDictionary, [self parseJSONResponse: NULL]);
        NSString* errorMsg = info[@"reason"] ?: info[@"error"];
        NSMutableDictionary* extra = $mdict({@"CBLServerErrorInfo", info});
        [self didFailWithStatus: _status message: errorMsg extra: extra];
    } else {
        [self didFinishLoading];
    }
}

// subclasses override this
- (void)didFinishLoading {
    LogTo(RemoteRequest, @"%@: Finished loading", self);
    [self clearConnection];
    [self respondWithResult: self error: nil];
}


static BOOL errorResponseMayBeJSON(NSHTTPURLResponse* response) {
    // CouchDB returns JSON with a MIME type of "text/plain;charset=utf-8" :-p
    NSString* contentType = response.MIMEType.lowercaseString;
    return [contentType hasPrefix: @"application/json"]
        || ([response.allHeaderFields[@"Server"] hasPrefix: @"CouchDB"]
            && [contentType hasPrefix: @"text/plain"]);
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

- (void) didReceiveData:(NSData *)data {
    [self appendJSON: data];
}

- (void) didFinishLoading {
    LogTo(RemoteRequest, @"%@: Finished loading", self);
    NSError* error = nil;
    id result = [self parseJSONResponse: &error];
    if (!result && !error)
        result = $dict();
    [self clearConnection];
    [self respondWithResult: result error: error];
}

@end
