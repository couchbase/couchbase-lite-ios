//
//  TDBrowserIDAuthorizer.m
//  TouchDB
//
//  Created by Jens Alfke on 1/9/13.
//
//

#import "TDBrowserIDAuthorizer.h"

@implementation TDBrowserIDAuthorizer

- (id) initWithAssertion:(NSString *)assertion {
    self = [super init];
    if (self) {
        if (!assertion)
            return nil;
        _assertion = [assertion copy];
    }
    return self;
}

@synthesize assertion=_assertion;

- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    // Auth is via cookie, which is automatically added by CFNetwork.
    return nil;
}

- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                          forRealm: (NSString*)realm
{
    // Auth is via cookie, which is automatically added by CFNetwork.
    return nil;
}

- (NSString*) loginPath {
    return @"/_browserid";
}

- (NSDictionary*) loginParameters {
    return @{@"assertion": _assertion};
}

@end
