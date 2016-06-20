//
//  OpenIDController
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <CouchbaseLite/CBLAuthenticator+OpenID.h>
@protocol OpenIDControllerDelegate;


NS_ASSUME_NONNULL_BEGIN


/** Controller for OpenID login. This class is cross-platform; the UI-related API is in
    category methods found in OpenIDController+UIKit.h and OpenIDController+AppKit.h. */
@interface OpenIDController : NSObject
{
    @private
    id _UIController;
    id _presentedUI;
}

/** Returns a callback block that you can pass to +[CBLAuthenticator OpenIDConnectAuthenticator:].
    It will take care of the login UI for you, automatically opening a panel (Mac OS) or a modal
    navigation controller (iOS) with a WebView in it, and dismissing it when the login finishes. */
+ (CBLOIDCLoginCallback) loginCallback;

- (instancetype) initWithLoginURL: (NSURL*)loginURL
                      redirectURL: (NSURL*)redirectURL
                         delegate: (id<OpenIDControllerDelegate>)delegate;

@property (readonly) NSURL* loginURL;
@property (readonly) id<OpenIDControllerDelegate> delegate;

// Internal:
- (BOOL) navigateToURL: (NSURL*)url;

@end


@interface OpenIDController (UI)
/** Displays the UI as a panel (Mac OS) or a modal view controller (iOS). */
- (void) presentUI;

/** Dismisses the UI displayed by -presentUI. */
- (void) closeUI;
@end


/** Delegate of an OpenIDController. */
@protocol OpenIDControllerDelegate <NSObject>

/** Sent if the user presses the Cancel button on the OpenID window. */
- (void) openIDControllerDidCancel: (OpenIDController*) openIDController;

/** Sent after authentication was successful. The assertion will be a long opaque string that
    should be sent to the origin site's OpenID authentication API. */
- (void) openIDController: (OpenIDController*) openIDController
    didSucceedWithAuthURL: (NSURL*)authURL;

- (void) openIDController: (OpenIDController*) openIDController
         didFailWithError: (NSString*)error
              description: (nullable NSString*)description;

@end


NS_ASSUME_NONNULL_END
