//
//  TDConnectionChangeTracker.m
//  TouchDB
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>

#import "TDConnectionChangeTracker.h"
#import "TDAuthorizer.h"
#import "TDRemoteRequest.h"
#import "TDMisc.h"
#import "TDStatus.h"
#import "MYURLUtils.h"


static SecTrustRef CopyTrustWithPolicy(SecTrustRef trust, SecPolicyRef policy);


@implementation TDConnectionChangeTracker

- (BOOL) start {
    if(_connection)
        return NO;
    [super start];
    _inputBuffer = [[NSMutableData alloc] init];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    request.timeoutInterval = 6.02e23;
    
    // Override the default Host: header to use the hostname _without_ the "." suffix
    // (the suffix appears to confuse Cloudant / BigCouch's HTTP server.)
    NSString* host = _databaseURL.host;
    if (_databaseURL.port)
        host = [host stringByAppendingFormat: @":%@", _databaseURL.port];
    [request setValue: host forHTTPHeaderField: @"Host"];

    // Add authorization:
    if (_authorizer) {
        [request setValue: [_authorizer authorizeURLRequest: request forRealm: nil]
                 forHTTPHeaderField: @"Authorization"];
    }

    // Add custom headers.
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        [request setValue: value forHTTPHeaderField: key];
    }];
    
    _connection = [[NSURLConnection connectionWithRequest: request delegate: self] retain];
    _startTime = CFAbsoluteTimeGetCurrent();
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, request.URL);
    return YES;
}


- (void) clearConnection {
    [_connection autorelease];
    _connection = nil;
    [_inputBuffer release];
    _inputBuffer = nil;
}


- (void) stopped {
    LogTo(ChangeTracker, @"%@: Stopped", self);
    [self clearConnection];
    [super stopped];
}


- (void) stop {
    if (_connection)
        [_connection cancel];
    [super stop];
}


- (bool) retryWithCredential {
    if (_authorizer || _challenged)
        return false;
    _challenged = YES;
    NSURLCredential* cred = [_databaseURL my_credentialForRealm: nil
                                           authenticationMethod: NSURLAuthenticationMethodHTTPBasic];
    if (!cred) {
        LogTo(ChangeTracker, @"Got 401 but no stored credential found (with nil realm)");
        return false;
    }

    [_connection cancel];
    self.authorizer = [[[TDBasicAuthorizer alloc] initWithCredential: cred] autorelease];
    LogTo(ChangeTracker, @"Got 401 but retrying with %@", _authorizer);
    [self clearConnection];
    [self start];
    return true;
}


- (void)connection:(NSURLConnection *)connection
        willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    id<NSURLAuthenticationChallengeSender> sender = challenge.sender;
    NSURLProtectionSpace* space = challenge.protectionSpace;
    NSString* authMethod = space.authenticationMethod;

    // Is this challenge for the DB hostname with the "." appended (the one in the URL request)?
    BOOL challengeIsForDottedHost = NO;
    NSString* host = space.host;
    if ([host hasSuffix: @"."] && !space.isProxy) {
        NSString* hostWithoutDot = [host substringToIndex: host.length - 1];
        challengeIsForDottedHost = ([hostWithoutDot caseInsensitiveCompare: _databaseURL.host] == 0);
    }

    if ($equal(authMethod, NSURLAuthenticationMethodServerTrust)) {
        // Verify trust of SSL server cert:
        SecTrustRef trust = challenge.protectionSpace.serverTrust;
        if (challengeIsForDottedHost) {
            // Update the policy with the correct original hostname (without the "." suffix):
            host = _databaseURL.host;
            SecPolicyRef policy = SecPolicyCreateSSL(YES, (CFStringRef)host);
            trust = CopyTrustWithPolicy(trust, policy);
            CFRelease(policy);
        } else {
            CFRetain(trust);
        }
        if ([TDRemoteRequest checkTrust: trust forHost: host]) {
            [sender useCredential: [NSURLCredential credentialForTrust: trust]
                    forAuthenticationChallenge: challenge];
        } else {
            [sender cancelAuthenticationChallenge: challenge];
        }
        CFRelease(trust);
        return;
    }

    _challenged = true;
    
    NSURLCredential* cred = nil;
    if (challengeIsForDottedHost && challenge.previousFailureCount == 0) {
        // Look up a credential for the original hostname without the "." suffix:
        host = _databaseURL.host;
        NSURLProtectionSpace* newSpace = [[NSURLProtectionSpace alloc]
                                                   initWithHost: host
                                                           port: space.port
                                                       protocol: space.protocol
                                                          realm: space.realm
                                           authenticationMethod: space.authenticationMethod];
        cred = [[NSURLCredentialStorage sharedCredentialStorage]
                                                defaultCredentialForProtectionSpace: newSpace];
        [newSpace release];
    }

    NSURLCredential* proposedCredential = challenge.proposedCredential;
    if (proposedCredential) {
        // Use the proposed credential unless the username doesn't match the one we want:
        if (!cred || [cred.user isEqualToString: proposedCredential.user]) {
            LogTo(ChangeTracker, @"%@: Using proposed credential '%@' for "
                  "{host=<%@>, port=%d, protocol=%@ realm=%@ method=%@}",
                  self, proposedCredential.user, host, (int)space.port, space.protocol, space.realm,
                  space.authenticationMethod);
            [sender performDefaultHandlingForAuthenticationChallenge: challenge];
            return;
        }
    }
    
    if (challengeIsForDottedHost && challenge.previousFailureCount == 0) {
        if (cred) {
            // Found a credential, so use it:
            LogTo(ChangeTracker, @"%@: Using credential '%@' for "
                                  "{host=<%@>, port=%d, protocol=%@ realm=%@ method=%@}",
                self, cred.user, host, (int)space.port, space.protocol, space.realm,
                space.authenticationMethod);
            [sender useCredential: cred forAuthenticationChallenge: challenge];
            return;
        }
    }
    
    // Give up:
    Log(@"%@: Continuing without credential for {host=<%@>, port=%d, protocol=%@ realm=%@ method=%@}",
        self, host, (int)space.port, space.protocol, space.realm,
        space.authenticationMethod);
    [sender continueWithoutCredentialForAuthenticationChallenge: challenge];
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    TDStatus status = (TDStatus) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(ChangeTracker, @"%@: Got response, status %d", self, status);
    if (status == 401) {
        // CouchDB says we're unauthorized but it didn't present a 'WWW-Authenticate' header
        // (it actually does this on purpose...) Let's see if we have a credential we can try:
        if ([self retryWithCredential])
            return;
    }
    if (TDStatusIsError(status)) {
        Warn(@"%@: Got status %i for %@", self, status, _databaseURL);
        [self connection: connection
              didFailWithError: TDStatusToNSError(status, self.changesFeedURL)];
    } else {
        _retryCount = 0;  // successful connection
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(ChangeTrackerVerbose, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    [_inputBuffer appendData: data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self clearConnection];
    [self failedWithError: error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // Now parse the entire response as a JSON document:
    NSData* input = [_inputBuffer retain];
    LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
    BOOL restart = NO;
    NSInteger numChanges = [self receivedPollResponse: input];
    if (numChanges < 0) {
        // Oops, unparseable response:
        if (_mode == kLongPoll && [input isEqualToData: [@"{\"results\":[\n"
                                                        dataUsingEncoding: NSUTF8StringEncoding]]) {
            // Looks like the connection got closed by a proxy (like AWS' load balancer) before
            // the server had an actual change to send.
            NSTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - _startTime;
            Warn(@"%@: Longpoll connection closed (by proxy?) after %.1f sec", self, elapsed);
            if (elapsed >= 30.0 && elapsed < _heartbeat) {
                self.heartbeat = elapsed * 0.75;
                restart = YES;
            }
        }
        if (!restart)
            [self setUpstreamError: @"Unparseable server response"];
    } else {
        // Poll again if there was no error, and either we're in longpoll mode or it looks like we
        // ran out of changes due to a _limit rather than because we hit the end.
        restart = (numChanges > 0 && (_mode == kLongPoll || numChanges == (NSInteger)_limit));
    }
    [input release];
    
    [self clearConnection];
    
    if (restart)
        [self start];       // Next poll...
    else
        [self stopped];
}

@end


static SecTrustRef CopyTrustWithPolicy(SecTrustRef trust, SecPolicyRef policy) {
#if TARGET_OS_IPHONE
    CFIndex nCerts = SecTrustGetCertificateCount(trust);
    CFMutableArrayRef certs = CFArrayCreateMutable(NULL, nCerts, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < nCerts; ++i)
        CFArrayAppendValue(certs, SecTrustGetCertificateAtIndex(trust, i));
    OSStatus err = SecTrustCreateWithCertificates(certs, policy, &trust);
    CAssertEq(err, noErr);
    return trust;
#else
    SecTrustSetPolicies(trust, policy);
    CFRetain(trust);
    return trust;
#endif
}
