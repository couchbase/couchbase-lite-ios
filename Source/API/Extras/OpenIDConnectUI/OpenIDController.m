//
//  OpenIDController.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//

#import "OpenIDController.h"


@interface OpenIDController (ContinuationHandling) <OpenIDControllerDelegate>
@end


@implementation OpenIDController
{
    CBLOIDCLoginContinuation _loginContinuation;
    NSString* _redirectURLStr;
}


@synthesize loginURL=_loginURL, delegate=_delegate;


+ (CBLOIDCLoginCallback) loginCallback {
    return ^(NSURL* loginURL, NSURL* redirectURL, CBLOIDCLoginContinuation continuation) {
        (void)[[self alloc] initWithLoginURL: loginURL
                                 redirectURL: redirectURL
                                continuation: continuation];
    };
}


- (instancetype) initWithLoginURL: (NSURL*)loginURL
                      redirectURL: (NSURL*)redirectURL
                         delegate: (id<OpenIDControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _loginURL = loginURL;
        _redirectURLStr = redirectURL.absoluteString;
        _delegate = delegate;
    }
    return self;
}


- (instancetype) initWithLoginURL: (NSURL*)loginURL
                      redirectURL: (NSURL*)redirectURL
                     continuation: (CBLOIDCLoginContinuation)continuation
{
    self = [self initWithLoginURL: loginURL redirectURL: redirectURL delegate: self];
    if (self) {
        _loginContinuation = continuation;
        [self presentUI];
    }
    return self;
}


- (BOOL) navigateToURL: (NSURL*)url {
    if (![url.absoluteString hasPrefix: _redirectURLStr])
        return YES;  // Ordinary URL, let the WebView handle it

    // Look at the URL query to see if it's an error or not:
    NSString* error = nil, *description = nil;
    NSURLComponents* comp = [NSURLComponents componentsWithURL: url resolvingAgainstBaseURL: YES];
    for (NSURLQueryItem* item in comp.queryItems) {
        if ([item.name isEqualToString: @"error"])
            error = item.value;
        else if ([item.name isEqualToString: @"error_description"])
            description = item.value;
    }

    if (error)
        [_delegate openIDController: self didFailWithError: error description: description];
    else
        [_delegate openIDController: self didSucceedWithAuthURL: url];
    return NO;
}


@end




@implementation OpenIDController (ContinuationHandling)

- (void) openIDControllerDidCancel: (OpenIDController*) openIDController {
    _loginContinuation(nil, nil);
    [self closeUI];
}

- (void) openIDController: (OpenIDController*) openIDController
    didSucceedWithAuthURL: (NSURL*)authURL;
{
    _loginContinuation(authURL, nil);
    [self closeUI];
}

- (void) openIDController: (OpenIDController*) openIDController
         didFailWithError: (NSString*)error
              description: (nullable NSString*)description
{
    NSDictionary* info = @{NSLocalizedDescriptionKey: error,
                           NSLocalizedFailureReasonErrorKey: (description ?: @"Login failed")};
    _loginContinuation(nil, [NSError errorWithDomain: NSURLErrorDomain code: NSURLErrorUnknown
                                            userInfo: info]);
    [self closeUI];
}

@end
