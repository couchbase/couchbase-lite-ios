//
//  OpenIDController.m
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//

#import "OpenIDController.h"


#define kFakeRedirectHost @"end.of.auth"
#define kFakeRedirectURLStr @"https://" kFakeRedirectHost "/"


@interface OpenIDController (ContinuationHandling) <OpenIDControllerDelegate>
@end


@implementation OpenIDController
{
    CBLOIDCLoginContinuation _loginContinuation;
    NSURL* _loginAuthBaseURL;
}


@synthesize loginURL=_loginURL, delegate=_delegate;


+ (CBLOIDCLoginCallback) loginCallback {
    return ^(NSURL* loginURL, NSURL* authBaseURL, CBLOIDCLoginContinuation continuation) {
        (void)[[self alloc] initWithLoginURL: loginURL
                                 authBaseURL: authBaseURL
                                continuation: continuation];
    };
}


- (instancetype) initWithLoginURL: (NSURL*)loginURL
                         delegate: (id<OpenIDControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        NSURLComponents* comp = [NSURLComponents componentsWithURL: loginURL resolvingAgainstBaseURL: YES];
        NSMutableArray<NSURLQueryItem*>* query = comp.queryItems.mutableCopy;
        for (NSUInteger i = 0; i < query.count; i++) {
            if ([query[i].name isEqualToString: @"redirect_uri"]) {
                query[i] = [NSURLQueryItem queryItemWithName: @"redirect_uri"
                                                       value: kFakeRedirectURLStr];
                break;
            }
        }
        comp.queryItems = query;
        _loginURL = comp.URL;
        _delegate = delegate;
    }
    return self;
}


- (instancetype) initWithLoginURL: (NSURL*)loginURL
                      authBaseURL: (NSURL*)authBaseURL
                     continuation: (CBLOIDCLoginContinuation)continuation
{
    self = [self initWithLoginURL: loginURL delegate: self];
    if (self) {
        _loginContinuation = continuation;
        _loginAuthBaseURL = authBaseURL;
        [self presentUI];
    }
    return self;
}


- (BOOL) navigateToURL: (NSURL*)url {
    if ([url.host caseInsensitiveCompare: kFakeRedirectHost] != 0)
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

    if (error) {
        // Tell the delegate about the error:
        [_delegate openIDController: self didFailWithError: error description: description];
        return NO;
    }

    // Tell the delegate login succeeded. Construct the auth URL by replacing the authBaseURl's
    // query string with the redirected-to URL's:
    comp = [NSURLComponents componentsWithURL: _loginAuthBaseURL
                      resolvingAgainstBaseURL: YES];
    comp.query = url.query;
    [_delegate openIDController: self didSucceedWithAuthURL: comp.URL];
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
