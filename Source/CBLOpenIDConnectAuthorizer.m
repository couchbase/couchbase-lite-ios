//
//  CBLOpenIDConnectAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/19/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//
//  https://openid.net/connect/
//  https://github.com/couchbase/sync_gateway/wiki/OIDC-Notes

#import "CBLOpenIDConnectAuthorizer.h"
#import "CBLMisc.h"
#import "MYErrorUtils.h"
#import "MYURLUtils.h"
#import <Security/Security.h>


UsingLogDomain(Sync);


#define kOIDCKeychainServiceName @"OpenID Connect"


@interface CBLOpenIDConnectAuthorizer ()
@property (readwrite) NSString* username;   // SG user name
@end


@implementation CBLOpenIDConnectAuthorizer
{
    CBLOIDCLoginCallback _loginCallback;    // App-provided callback to log into the OP
    NSURL* _remoteURL;          // The remote database URL
    NSURL* _authURL;            // The OIDC authentication URL redirected to by the OP
    NSString* _IDToken;         // Persistent ID token, when logged-in
    NSString* _refreshToken;    // Persistent refresh token, when logged-in or refreshing login
    BOOL _haveSessionCookie;    // YES if the server set a login session cookie
}

@synthesize username=_username;
#if DEBUG
@synthesize IDToken=_IDToken, refreshToken=_refreshToken;
#endif


- (instancetype) initWithCallback: (CBLOIDCLoginCallback)callback {
    self = [super init];
    if (self) {
        _loginCallback = callback;
    }
    return self;
}


// internal use only
- (instancetype) initWithRemoteURL: (NSURL*)remoteURL {
    self = [super init];
    if (self) {
        _remoteURL = remoteURL;
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"%@[%@]", self.class, _remoteURL.my_baseURL];
}


- (BOOL) parseTokensFrom: (NSDictionary*)tokens {
    NSString* idToken = tokens[@"id_token"];
    if (!idToken)
        return NO;
    _IDToken = idToken;
    _refreshToken = tokens[@"refresh_token"];
    self.username = tokens[@"name"];
    _haveSessionCookie = (tokens[@"session_id"] != nil);
    return YES;
}


#pragma mark - LOGIN:


- (NSArray*) loginRequestForSite: (NSURL*)site {
    // Look for ID/refresh tokens in the Keychain if we haven't already:
    if (!_remoteURL) {
        _remoteURL = site;
        [self loadTokens];
    }

    NSString* path;
    if (_IDToken)
        path = @"_session";
    else if (_refreshToken)
        path = [@"_oidc_refresh?refresh_token=" stringByAppendingString:
                                                            CBLEscapeURLParam(_refreshToken)];
    else if (_authURL)
        path = [@"_oidc_callback?" stringByAppendingString: _authURL.query];
    else
        path = @"_oidc_challenge";
    return @[@"GET", path];
}


- (void) loginResponse: (NSDictionary*)jsonResponse
               headers: (NSDictionary*)headers
                 error: (NSError*)error
          continuation: (void (^)(BOOL loginAgain, NSError* continuationError))continuationBlock
{
    if (error && ![error my_hasDomain: CBLHTTPErrorDomain code: kCBLStatusUnauthorized]) {
        // If there's some non-401 error, just pass it on
        continuationBlock(NO, error);
        return;
    }

    if (_IDToken) {
        if (error) {
            if (_haveSessionCookie) {
                // Thought we had a session cookie but we don't; try sending the ID token next:
                _haveSessionCookie = NO;
            } else if (_refreshToken) {
                // If the ID token doesn't work, forget it and try the refresh token next:
                _IDToken = nil;
            }
            continuationBlock(YES, nil);
            return;
        }

    } else if (_refreshToken || _authURL) {
        // Logging in with an authURL from the OP, or refreshing the ID token:
        if (error) {
            _authURL = nil;
            if (_refreshToken) {
                // Refresh failed; go back to login state:
                _refreshToken = nil;
                self.username = nil;
                [self deleteTokens: NULL];
                continuationBlock(YES, nil);
                return;
            }

        } else {
            // Generated or refreshed ID token:
            if ([self parseTokensFrom: jsonResponse]) {
                LogTo(Sync, @"%@: Logged in as %@ !", self, _username);
                [self saveTokens: jsonResponse error: NULL];
            } else {
                error = CBLStatusToNSErrorWithInfo(kCBLStatusUpstreamError,
                                                   @"Server didn't return a refreshed ID token",
                                                   nil, nil);
            }
        }

    } else {
        // Login challenge: get the info & ask the app callback to log into the OP:
        NSString* login = nil;
        NSDictionary* challenge = error.userInfo[@"AuthChallenge"];
        if ($equal(challenge[@"Scheme"], @"OIDC"))
            login = challenge[@"login"];
        if (login) {
            LogTo(Sync, @"%@: Got OpenID Connect login URL: <%@>", self, login);
            [self continueAsyncLoginWithURL: [NSURL URLWithString: login]
                               continuation: continuationBlock];
            return; // don't call the continuation block yet
        } else {
            error = CBLStatusToNSErrorWithInfo(kCBLStatusUpstreamError,
                                                @"Server didn't provide an OpenID login URL",
                                                nil, nil);
        }
    }

    // by default, keep going immediately:
    continuationBlock(NO, error);
}


- (void) continueAsyncLoginWithURL: (NSURL*)loginURL
                      continuation: (void (^)(BOOL loginAgain, NSError* continuationError))continuationBlock
{
    LogTo(Sync, @"%@: Calling app login callback block on main thread...", self);
    NSURL* authBaseURL = [_remoteURL URLByAppendingPathComponent: @"_oidc_callback"];
    dispatch_async(dispatch_get_main_queue(), ^{
        _loginCallback(loginURL, authBaseURL, ^(NSURL* authURL, NSError* error) {
            if (authURL) {
                LogTo(Sync, @"%@: App login callback returned authURL=<%@>",
                      self, authURL.absoluteString);
                // Verify that the authURL matches the site:
                if ([authURL.host caseInsensitiveCompare: _remoteURL.host] != 0
                    || !$equal(authURL.port, _remoteURL.port)
                    || !$equal(authURL.path, [_remoteURL.path stringByAppendingPathComponent: @"_oidc_callback"]))
                {
                    Warn(@"%@: App-provided authURL <%@> doesn't match server URL; ignoring it",
                         self, authURL.absoluteString);
                    authURL = nil;
                    error = [NSError errorWithDomain: NSURLErrorDomain
                                                code: NSURLErrorBadURL
                                            userInfo: nil];
                }
            }
            if (authURL) {
                _authURL = authURL;
                continuationBlock(YES, nil);
            } else {
                if (!error)
                    error = [NSError errorWithDomain: NSURLErrorDomain
                                                code: NSURLErrorUserCancelledAuthentication
                                            userInfo: nil];
                LogTo(Sync, @"%@: App login callback returned error=%@",
                      self, error.my_compactDescription);
                continuationBlock(NO, error);
            }
        });
    });
}


// Auth phase (when we have the ID token):

- (BOOL) authorizeURLRequest: (NSMutableURLRequest*)request {
    if (_IDToken && !_haveSessionCookie) {
        NSString* auth = [@"Bearer " stringByAppendingString: _IDToken];
        [request addValue: auth forHTTPHeaderField: @"Authorization"];
        return YES;
    } else {
        return NO;
    }
}


#pragma mark - TOKEN PERSISTENCE:


+ (BOOL) forgetIDTokensForServer: (NSURL*)serverURL error: (NSError**)outError {
    CBLOpenIDConnectAuthorizer* auth = [[self alloc] initWithRemoteURL: serverURL];
    return [auth deleteTokens: outError];
}


- (NSMutableDictionary*) keychainAttributes {
    // 'label' is the item name shown in Keychain Access.
    // 'service' is shown as 'Where'.
    Assert(_remoteURL);
    NSString* account = _remoteURL.my_baseURL.absoluteString;
    NSString* label = $sprintf(@"%@ OpenID Connect tokens", _remoteURL.host);
    return [@{ (__bridge id)kSecClass:        (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService:  account,
               (__bridge id)kSecAttrAccount:  kOIDCKeychainServiceName,
               (__bridge id)kSecAttrLabel:    label,
             } mutableCopy];
}


- (BOOL) loadTokens {
    NSMutableDictionary* attrs = self.keychainAttributes;
    attrs[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = NULL;
    OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)attrs, &result);
    if (err || result == NULL) {
        if (err == errSecItemNotFound)
            LogTo(Sync, @"%@: No ID token found in Keychain", self);
        else
            Warn(@"%@: Couldn't load ID token: OSStatus %d", self, (int)err);
        return NO;
    }
    NSDictionary* tokens = $castIf(NSDictionary,
                                   [CBLJSON JSONObjectWithData: CFBridgingRelease(result)]);
    if ([self parseTokensFrom: tokens])
        LogTo(Sync, @"%@: Read ID token from Keychain", self);
    return YES;
}


- (BOOL) saveTokens: (NSDictionary*)tokens error: (NSError**)outError {
    if (!tokens)
        return [self deleteTokens: outError];
    NSData* itemData = [CBLJSON dataWithJSONObject: tokens];
    NSDate* now = [NSDate date];
    NSMutableDictionary* attrs = self.keychainAttributes;
    attrs[(__bridge id)kSecValueData] = itemData;
    attrs[(__bridge id)kSecAttrCreationDate] = now;
    attrs[(__bridge id)kSecAttrModificationDate] = now;
    attrs[(__bridge id)kSecAttrDescription] = @"OpenID Connect token"; // 'Kind' in Keychain Access

    CFTypeRef result = NULL;
    OSStatus err = SecItemAdd((__bridge CFDictionaryRef)attrs, &result);
    if (err == errSecDuplicateItem) {
        if ([self _deleteTokens] == noErr)
            err = SecItemAdd((__bridge CFDictionaryRef)attrs, &result);
    }
    if (err) {
        Warn(@"%@: Couldn't save ID token: OSStatus %d", self, (int)err);
        return MYReturnError(outError, err, NSOSStatusErrorDomain,
                             @"Unable to save ID token to Keychain");
    }
    LogTo(Sync, @"%@: Saved ID token to Keychain", self);
    return YES;
}


- (OSStatus) _deleteTokens {
    NSMutableDictionary* attrs = self.keychainAttributes;
    return SecItemDelete((__bridge CFDictionaryRef)attrs);
}


- (BOOL) deleteTokens: (NSError**)outError {
    OSStatus err = [self _deleteTokens];
    if (err == noErr) {
        LogTo(Sync, @"%@: Deleted ID token from Keychain", self);
    } else if (err != errSecItemNotFound) {
        Warn(@"%@: Couldn't delete ID token: OSStatus %d", self, (int)err);
        return MYReturnError(outError, err, NSOSStatusErrorDomain,
                             @"Unable to delete ID token");
    }
    return YES;
}


@end
