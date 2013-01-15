//
//  TDBrowserIDAuthorizer.m
//  TouchDB
//
//  Created by Jens Alfke on 1/9/13.
//
//

#import "TDBrowserIDAuthorizer.h"


static NSMutableDictionary* sAssertions;


@implementation TDBrowserIDAuthorizer


+ (NSURL*) originForSite: (NSURL*)url {
    NSString* scheme = url.scheme.lowercaseString;
    NSMutableString* str = [NSMutableString stringWithFormat: @"%@://%@",
                            scheme, url.host.lowercaseString];
    NSNumber* port = url.port;
    if (port) {
        int defaultPort = [scheme isEqualToString: @"https"] ? 443 : 80;
        if (port.intValue != defaultPort)
            [str appendFormat: @":%@", port];
    }
    [str appendString: @"/"];
    return [NSURL URLWithString: str];
}


+ (void) registerAssertion: (NSString*)assertion
           forEmailAddress: (NSString*)email
                    toSite: (NSURL*)site
{
    @synchronized(self) {
        if (!sAssertions)
            sAssertions = [NSMutableDictionary dictionary];
        id key = @[email, [self originForSite: site]];
        sAssertions[key] = assertion;
    }
}


+ (NSString*) takeAssertionForEmailAddress: (NSString*)email
                                      site: (NSURL*)site
{
    @synchronized(self) {
        id key = @[email, [self originForSite: site]];
        NSString* assertion = sAssertions[key];
        //[sAssertions removeObjectForKey: key];
        return assertion;
    }
}


@synthesize emailAddress=_emailAddress;


- (id) initWithEmailAddress: (NSString*)emailAddress {
    self = [super init];
    if (self) {
        if (!emailAddress)
            return nil;
        _emailAddress = [emailAddress copy];
    }
    return self;
}


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


- (NSDictionary*) loginParametersForSite: (NSURL*)site {
    NSString* assertion = [[self class] takeAssertionForEmailAddress: _emailAddress site: site];
    if (!assertion)
        return nil;
    return @{@"assertion": assertion};
}

@end
