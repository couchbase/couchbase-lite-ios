//
//  CBLAuthenticator+OpenID.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/6/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthenticator.h"

NS_ASSUME_NONNULL_BEGIN


/** Callback that will be passed to your CBLOIDCLoginCallback. You should call this callback when
    your login UI completes, so that Couchbase Lite's replicator can continue or stop.
    @param redirectedURL  The authentication URL to which the WebView was redirected.
                It will have the same host and path as the redirectURL passed to your login
                callback, plus extra query parameters appended.
                If login did not complete successfully, pass nil.
    @param error  If the login UI failed, pass the error here (and a nil authURL.) As a special
                case, if both error and authURL are nil, it's interpreted as an authentication-
                canceled error. */
typedef void (^CBLOIDCLoginContinuation)(NSURL* __nullable redirectedURL, NSError* __nullable error);


/** Callback block given when creating an OpenID Connect authenticator. The block will be called
    when the OpenID Connect login flow requires the user to authenticate with the Originating Party
    (OP), the site at which they have an account.
 
    The easiest way to provide this callback is to add the classes in Extras/OpenIDConnectUI to
    your app target, and then simply call [OpenIDController loginCallback].

    If you want to implement your own UI, then this block should open a modal web view starting at
    the given loginURL, then return. Just make sure you hold onto the CBLOIDCLoginContinuation 
    block, because you MUST call it later, or the replicator will never finish logging in!

    Wait for the web view to redirect to a URL whose host and path are the same as the given
    redirectURL (the query string after the path will be different, though.) Instead of following
    the redirect, close the web view and call the given continuation block with the redirected
    URL (and a nil error.)

    Your modal web view UI should provide a way for the user to cancel, probably by adding a
    Cancel button outside the web view. If the user cancels, call the continuation block with
    a nil URL and a nil error.
 
    If something else goes wrong, like an error loading the login page in the web view, call the
    continuation block with that error and a nil URL. */
typedef void (^CBLOIDCLoginCallback)(NSURL* loginURL, NSURL* redirectURL, CBLOIDCLoginContinuation);


@interface CBLAuthenticator (OpenID)

/** Creates an authenticator for use with OpenID Connect (NOT any earlier versions of OpenID.)
    This authenticator will use an ID token saved in the Keychain; if there isn't one, or if it's
    expired and can't be renewed, then a login is required, which will involve user interaction 
    with a login web page run by the identity provider. Since Couchbase Lite doesn't have its own
    UI, it delegates this task to your app. 
 
    The replicator will call your login callback, passing it the URL of this web page and the URL
    to which the identity provider will redirect when the login is complete. You then open a
    WebView and let the login happen asynchronously. When it completes, you call the
    CBLOIDCLoginContinuation callback that was also passed to your login callback.

    Please see the docs of the CBLOIDCLoginCallback and CBLOIDCLoginContinuation types for more
    details. */
+ (id<CBLAuthenticator>) OpenIDConnectAuthenticator: (CBLOIDCLoginCallback)callback;

@end

NS_ASSUME_NONNULL_END
