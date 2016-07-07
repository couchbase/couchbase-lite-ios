//
//  CBLRemoteLogin.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/8/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteLogin.h"
#import "CBLRemoteSession.h"
#import "CBLRemoteRequest.h"
#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "MYURLUtils.h"


UsingLogDomain(Sync);


@implementation CBLRemoteLogin
{
    NSURL* _remoteURL;
    NSString* _localUUID;
    CBLRemoteSession* _remoteSession;
    id<CBLRemoteRequestDelegate> _requestDelegate;
    void(^_continuation)(NSError*);
}


- (instancetype) initWithURL: (NSURL*)remoteURL
                   localUUID: (NSString*)localUUID
                     session: (CBLRemoteSession*)session
             requestDelegate: (id<CBLRemoteRequestDelegate>)requestDelegate
                continuation: (void(^)(NSError*))continuation
{
    Assert(remoteURL);
    Assert(session);
    self = [super init];
    if (self) {
        _remoteURL = remoteURL;
        _localUUID = [localUUID copy];
        _remoteSession = session;
        _requestDelegate = requestDelegate;
        _continuation = continuation;
    }
    return self;
}


- (instancetype) initWithURL: (NSURL*)remoteURL
                   localUUID: (NSString*)localUUID
                  authorizer: (id<CBLAuthorizer>)authorizer
                continuation: (void(^)(NSError*))continuation
{
    NSURLSessionConfiguration* config = [[CBLRemoteSession defaultConfiguration] copy];
    CBLRemoteSession* session = [[CBLRemoteSession alloc] initWithConfiguration: config
                                                                        baseURL: remoteURL
                                                                       delegate: nil
                                                                     authorizer: authorizer
                                                                  cookieStorage: nil];
    return [self initWithURL: remoteURL
                   localUUID: localUUID
                     session: session
             requestDelegate: nil
                continuation: continuation];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _remoteURL];
}


- (void)dealloc
{
    Log(@"DEALLOC %@", self);
    Assert(!_continuation); // must already have been called
}


- (void) start {
    CFRetain((__bridge CFTypeRef)self); // keep self from being released until it's done
    _remoteSession.authorizer.remoteURL = _remoteURL;
    _remoteSession.authorizer.localUUID = _localUUID;
    if ([_remoteSession.authorizer conformsToProtocol: @protocol(CBLSessionCookieAuthorizer)]) {
        // Sync Gateway session API is at /db/_session; try that first
        [self checkSessionAtPath: @"_session"];
    } else {
        [self login];
    }
}


- (void) checkSessionAtPath: (NSString*)sessionPath {
    // First check whether a session exists
    [_remoteSession startRequest: @"GET"
                            path: sessionPath
                            body: nil
                    onCompletion: ^(id result, NSError *error)
    {
        if (error) {
            // If not at /db/_session, try CouchDB location /_session
            if (error.code == kCBLStatusNotFound && $equal(sessionPath, @"_session")) {
                [self checkSessionAtPath: @"/_session"];
                return;
            } else if (error.code == kCBLStatusUnauthorized) {
                [self login];
            } else {
                LogTo(Sync, @"%@: Session check failed: %@",
                      self, error.my_compactDescription);
                [self finishedWithError: error];
            }
        } else {
            NSString* username = $castIf(NSString, result[@"userCtx"][@"name"]);
            if (username) {
                // Found a login session!
                LogTo(Sync, @"%@: Active session, logged in as '%@'", self, username);
                [self finishedWithError: nil];
            } else {
                // No current login session, so continue to regular login:
                [self login];
            }
        }
    }];
}


// If there is no login session, attempt to log in, if the authorizer knows the parameters.
- (void) login {
    id<CBLLoginAuthorizer> loginAuth = $castIfProtocol(CBLLoginAuthorizer, _remoteSession.authorizer);
    NSArray* login = [loginAuth loginRequest];
    if (login == nil) {
        [self finishedWithError: nil];
        return;
    }

    NSString* method = login[0];
    NSString* loginPath = login[1];
    id loginParameters = login.count >= 3 ? login[2] : nil;

    LogTo(Sync, @"%@: Logging in with %@ at %@ ...",
          self, _remoteSession.authorizer.class, $url(loginPath).my_sanitizedString);
    __block CBLRemoteJSONRequest* rq;
    rq = [_remoteSession startRequest: method
                                 path: loginPath
                                 body: loginParameters
                         onCompletion: ^(id result, NSError *error)
    {
        if ([loginAuth respondsToSelector: @selector(loginResponse:headers:error:continuation:)]) {
            [loginAuth loginResponse: result
                             headers: rq.responseHeaders
                               error: error
                        continuation: ^(BOOL loginAgain, NSError* continuationError)
            {
                [_remoteSession doAsync:^{
                    if (loginAgain) {
                        [self login];
                    } else {
                        [self finishedWithError: continuationError];
                    }
                }];
            }];
        } else {
            LogTo(Sync, @"%@: Successfully logged in!", self);
            [self finishedWithError: error];
        }
    }];
}


- (void) finishedWithError: (NSError*)error {
    if (error)
        LogTo(Sync, @"%@: Login error: %@", self, error.my_compactDescription);
    __typeof(_continuation) continuation = _continuation;
    _continuation = nil;
    continuation(error);
    CFRelease((__bridge CFTypeRef)self);    // balances the CFRetain in -start
}


@end
