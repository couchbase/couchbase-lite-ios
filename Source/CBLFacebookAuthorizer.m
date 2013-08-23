//
//  CBLFacebookAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/7/13.
//
//

#import "CBLFacebookAuthorizer.h"
#import "MYURLUtils.h"


#define kLoginParamAccessToken @"access_token"


static NSMutableDictionary* sRegisteredTokens;


@implementation CBLFacebookAuthorizer
{
    NSString* _email;
}


- (id)initWithEmailAddress:(NSString *)email {
    self = [super init];
    if (self) {
        if (!email)
            return nil;
        _email = email;
    }
    return self;
}


+ (bool) registerToken: (NSString*)token
       forEmailAddress: (NSString*)email
               forSite: (NSURL*)site
{
    id key = @[email, site.my_baseURL.absoluteString];
    @synchronized(self) {
        if (!sRegisteredTokens)
            sRegisteredTokens = [NSMutableDictionary dictionary];
        [sRegisteredTokens setValue: token forKey: key];
    }
    return true;
}


- (NSString*) tokenForSite: (NSURL*)site {
    id key = @[_email, site.my_baseURL.absoluteString];
    @synchronized([self class]) {
        return sRegisteredTokens[key];
    }
}


- (NSString*) loginPathForSite: (NSURL*)site {
    return [site.path stringByAppendingPathComponent: @"_facebook"];
}


- (NSDictionary*) loginParametersForSite: (NSURL*)site {
    NSString* token = [self tokenForSite: site];
    return token ? @{kLoginParamAccessToken: token} : nil;
}


- (NSString*) authorizeURLRequest: (NSMutableURLRequest*)request
                         forRealm: (NSString*)realm
{
    return nil; // no-op
}


- (NSString*) authorizeHTTPMessage: (CFHTTPMessageRef)message
                          forRealm: (NSString*)realm
{
    return nil; // no-op
}

@end




TestCase(CBLFacebookAuthorizer) {
    NSString* token = @"pyrzqxgl";
    NSURL* site = [NSURL URLWithString: @"https://example.com/database"];
    NSString* email = @"jimbo@example.com";

    CBLFacebookAuthorizer* auth = [[CBLFacebookAuthorizer alloc] initWithEmailAddress: email];

    // Register and retrieve the sample token:
    CAssert([CBLFacebookAuthorizer registerToken: token
                                 forEmailAddress: email forSite: site]);
    NSString* gotToken = [auth tokenForSite: site];
    CAssertEqual(gotToken, token);

    // Try a variant form of the URL:
    gotToken = [auth tokenForSite: [NSURL URLWithString: @"HttpS://example.com:443/some/other/path"]];
    CAssertEqual(gotToken, token);

    CAssertEqual([auth loginParametersForSite: site], (@{@"access_token": token}));
}
