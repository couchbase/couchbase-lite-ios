//
//  CBLCookieStorage.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/18/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLCookieStorage.h"
#import "CBLDatabase.h"
#import "CBLMisc.h"
#import "Logging.h"


#define kLocalDocKeyPrefix @"cbl_cookie_storage"
#define kLocalDocCookiesKey @"cookies"

@interface CBLCookieStorage ()
- (NSString*) localDocKey;
- (void) loadCookies;
- (BOOL) deleteCookie: (NSHTTPCookie*)aCookie outIndex: (NSUInteger*)outIndex;
- (BOOL) saveCookies: (NSError **)error;
- (BOOL) isExpiredCookie: (NSHTTPCookie*)cookie;
- (BOOL) isDomainMatchedBetweenCookie: (NSHTTPCookie*)cookie andUrl: (NSURL*)url;
- (BOOL) isPathMatchedBetweenCookie: (NSHTTPCookie*)cookie andUrl: (NSURL*)url;
@end


@implementation CBLCookieStorage
{
    NSMutableArray* _cookies;
    CBLDatabase* _db;
    NSString* _storageKey;
}

@synthesize cookieAcceptPolicy = _cookieAcceptPolicy;

- (instancetype) initWithDB: (CBLDatabase*)db storageKey: (NSString*)storageKey {
    self = [super init];
    if (self) {
        Assert(db != nil, @"database cannot be nil.");
        Assert(storageKey != nil, @"storageKey cannot be nil.");

        _db = db;
        _storageKey = storageKey;

        self.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;

        [self loadCookies];
    }
    return self;
}


- (NSArray*)cookies {
     NSMutableArray *cookies = [NSMutableArray array];
    [_cookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSHTTPCookie* cookie = (NSHTTPCookie*)obj;
        if (![self isExpiredCookie: cookie]) {
            [cookies addObject: cookie];
        }
    }];
    return cookies;
}


- (NSArray*) cookiesForURL: (NSURL*)url {
    if (!url)
        return nil;

    NSMutableArray* cookies = [NSMutableArray array];
    [_cookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSHTTPCookie* cookie = (NSHTTPCookie*)obj;

        // Check whether the cookie is expired:
        if ([self isExpiredCookie: cookie])
            return;

        // NOTE:
        // From https://developer.apple.com/library/ios/documentation/Cocoa/Reference/Foundation/Classes/NSHTTPCookie_Class/index.html :
        // NSHTTPCookiePort : An NSString object containing comma-separated integer values specifying
        // the ports for the cookie. Only valid for Version 1 cookies or later. The default value is
        // an empty string (""). This cookie attribute is optional.
        //
        // However, there are a few discrepancies based on a test result as of 02/23/2015:
        // 1. Setting NSHTTPCookiePort also has effect on cookies version 0.
        // 2. Setting multiple values with comma-separated doesn't work. Only the first value is
        //    accepted.
        // 3. Setting to an empty string ("") results to a port number 0.
        //
        // So we are maintaining the same behaviors as what we have seen in the test result.
        //
        // If the cookie has no port list this method returns nil and the cookie will be sent
        // to any port. Otherwise, the cookie is only sent to ports specified in the port list.
        if ([cookie.portList count] > 0 && ![cookie.portList containsObject: url.port])
            return;

        // If a cookie is secure, it will be sent to only the secure urls:
        NSString* urlScheme = [url.scheme lowercaseString];
        if (cookie.isSecure && ![urlScheme isEqualToString: @"https"])
            return;

        //
        // Matching Rules:
        //
        // Domain Matching Rules:
        // 1. Matched if cookie domain == URL Host (Case insensitively).
        // 2. Or if Cookie domain begins with '.' (global domain cookies), matched if the URL host
        //    has the same domain as the cookie domain after dot. A url, which is a submodule of
        //    the cookie domain is also counted.
        //
        // Path Matching Rules (After the domain and the host are matched):
        // 1. Matched if the cookie path is a '/' or '<EMPTY>' string regardless of the url path.
        // 2. Or matched if the cookie path is a prefix of the url path.
        //
        if ([self isDomainMatchedBetweenCookie: cookie andUrl: url] &&
            [self isPathMatchedBetweenCookie: cookie andUrl: url])
            [cookies addObject:cookie];
    }];

    return cookies;
}


- (NSArray*) sortedCookiesUsingDescriptors: (NSArray*)sortOrder {
    NSMutableArray* cookies = [NSMutableArray array];
    [_cookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSHTTPCookie* cookie = (NSHTTPCookie*)obj;
        if (![self isExpiredCookie: cookie]) {
            [cookies addObject:cookie];
        }
    }];

    return [cookies sortedArrayUsingDescriptors: sortOrder];
}


- (void) setCookie: (NSHTTPCookie*)cookie {
    if (!cookie)
        return;

    if (self.cookieAcceptPolicy == NSHTTPCookieAcceptPolicyNever)
        return;

    NSUInteger idx;
    if ([self deleteCookie: cookie outIndex: &idx])
        [_cookies insertObject:cookie atIndex:idx];
    else
        [_cookies addObject: cookie];

    NSError* error;
    if (![self saveCookies: &error])
        Warn(@"%@: Cannot save the cookie %@ with an error : %@", self, cookie, error);
}

/*
   The behavior of NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain and this method on 
   NSHTTPCookieStorage are unclear. NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain doesn't
   seem to be taking into consideration.
- (void) setCookies: (NSArray*)cookies forURL: (NSURL*)theURL mainDocumentURL: (NSURL*)mainDocumentURL {
    if (self.cookieAcceptPolicy == NSHTTPCookieAcceptPolicyNever)
        return;

    if (self.cookieAcceptPolicy == NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain &&
        !mainDocumentURL)
        return;

    for (NSHTTPCookie* cookie in cookies) {
        NSUInteger idx;
        if ([self deleteCookie: cookie outIndex: &idx])
            [_cookies insertObject:cookie atIndex:idx];
        else
            [_cookies addObject: cookie];
    }

    NSError* error;
    if (![self saveCookies: &error])
        Warn(@"%@: Cannot save cookies with an error : %@", self, error);
}
*/


- (void) deleteCookie: (NSHTTPCookie*)aCookie {
    if (!aCookie)
        return;

    // NOTE: There is discrepancy about path matching when observing NSHTTPCookieStore behaviors:
    // 1. When adding or deleting a cookie, Comparing the cookie paths is case-insensitive.
    // 2. When getting cookies for a url, Matching the cookie paths is case-sensitive.
    [self deleteCookie:aCookie outIndex:nil];

    NSError* error;
    if (![self saveCookies: &error]) {
        Warn(@"%@: Cannot save cookies with an error : %@", self, error);
    }
}


- (void) deleteAllCookies {
    [_cookies removeAllObjects];

    NSError* error;
    if (![self saveCookies: &error]) {
        Warn(@"%@: Cannot save cookies with an error : %@", self, error);
    }
}


- (void) dealloc {
    _db = nil;
    _cookies = nil;
}


# pragma mark - Private


- (NSString*) localDocKey {
    return [NSString stringWithFormat: @"%@_%@", kLocalDocKeyPrefix, _storageKey];
}


- (BOOL) deleteCookie: (NSHTTPCookie*)aCookie outIndex: (NSUInteger*)outIndex {
    __block NSInteger foundIndex = -1;
    [_cookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSHTTPCookie* cookie = (NSHTTPCookie*)obj;
        if ([aCookie.name caseInsensitiveCompare: cookie.name] == 0 &&
            [aCookie.domain caseInsensitiveCompare: cookie.domain] == 0 &&
            [aCookie.path caseInsensitiveCompare: cookie.path] == 0) {
            foundIndex = idx;
            *stop = YES;
        }
    }];

    if (foundIndex >= 0)
        [_cookies removeObjectAtIndex:foundIndex];

    if (outIndex)
        *outIndex = foundIndex;

    return (foundIndex >= 0);
}

- (void) loadCookies {
    NSString* key = [self localDocKey];
    NSDictionary* doc = [_db existingLocalDocumentWithID: key];
    NSArray* allCookies = [doc objectForKey: kLocalDocCookiesKey];

    _cookies = [NSMutableArray array];
    [allCookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSDictionary *props = [self cookiePropertiesFromJSONDocument: obj];
        NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties: props];
        if (cookie)
            [_cookies addObject: cookie];
    }];
}


- (BOOL) saveCookies: (NSError **)error {
    NSMutableArray* cookies = [NSMutableArray array];
    [_cookies enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop) {
        NSHTTPCookie* cookie = (NSHTTPCookie*)obj;
        if ([self shouldSaveCookie:cookie]) {
            NSDictionary *props = [self JSONDocumentFromCookieProperties: cookie.properties];
            [cookies addObject: props];
        }
    }];

    NSString* docKey = [self localDocKey];
    return [_db putLocalDocument: @{kLocalDocCookiesKey: cookies} withID: docKey error: error];
}


- (BOOL) isExpiredCookie: (NSHTTPCookie*)cookie {
    NSDate* expDate = cookie.expiresDate;
    return (expDate && [expDate compare: [NSDate date]] != NSOrderedDescending);
}


- (BOOL) shouldSaveCookie: (NSHTTPCookie*)cookie {
    return !cookie.sessionOnly && cookie.expiresDate && ![self isExpiredCookie: cookie];
}


- (BOOL) isDomainMatchedBetweenCookie: (NSHTTPCookie*)cookie andUrl: (NSURL*)url {
    NSString* urlHost = [url.host lowercaseString];
    NSString* cookieDomain = [cookie.domain lowercaseString];

    BOOL domainMatched = NO;
    if ([cookieDomain hasPrefix: @"."]) { // global domain cookie.
        NSString* domainAfterDot = [cookieDomain substringFromIndex: 1];
        domainMatched = [urlHost hasSuffix: domainAfterDot];
    } else
        domainMatched = [urlHost isEqualToString: cookieDomain];

    return domainMatched;
}


- (BOOL) isPathMatchedBetweenCookie: (NSHTTPCookie*)cookie andUrl: (NSURL*)url {
    NSString* cookiePath = cookie.path;
    if (cookiePath.length == 0 || [cookiePath isEqualToString: @"/"])
        return YES;

#ifdef GNUSTEP
    NSString* urlPath = [url pathWithEscapes];
#else
    #ifdef __OBJC_GC__
    NSString* urlPath = NSMakeCollectable(CFURLCopyPath((CFURLRef)url));
    #else
    NSString* urlPath = (__bridge_transfer NSString *)CFURLCopyPath((__bridge CFURLRef)url);
    #endif
#endif

    if (![urlPath hasPrefix: cookiePath])
        return NO;

    BOOL matched =
        (urlPath.length == cookiePath.length) ||
        [urlPath characterAtIndex: cookiePath.length -
            ([cookiePath hasSuffix: @"/"] ? 1 : 0)] == '/';
    return matched;
}


- (NSDictionary*) JSONDocumentFromCookieProperties: (NSDictionary*)props {
    if (props[NSHTTPCookieExpires]) {
        NSMutableDictionary* newProps = [NSMutableDictionary dictionaryWithDictionary: props];
        newProps[NSHTTPCookieExpires] = [CBLJSON JSONObjectWithDate: props[NSHTTPCookieExpires]];
        props = newProps;
    }
    return props;
}


- (NSDictionary*) cookiePropertiesFromJSONDocument: (NSDictionary*)props {
    if (props[NSHTTPCookieExpires]) {
        NSMutableDictionary* newProps = [NSMutableDictionary dictionaryWithDictionary: props];
        newProps[NSHTTPCookieExpires] = [CBLJSON dateWithJSONObject: props[NSHTTPCookieExpires]];
        props = newProps;
    }
    return props;
}

@end

@implementation CBLCookieStorage (NSURLRequestResponse)

- (void) addCookieHeaderForRequest: (NSMutableURLRequest*)request {
    request.HTTPShouldHandleCookies = NO;
    NSArray* cookies = [self cookiesForURL: request.URL];
    if ([cookies count] > 0) {
        NSDictionary* cookieHeaders = [NSHTTPCookie requestHeaderFieldsWithCookies: cookies];
        [cookieHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
}

- (void) setCookieForResponse: (NSHTTPURLResponse*)response {
    NSArray* cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:
                        response.allHeaderFields forURL: response.URL];
    for (NSHTTPCookie* cookie in cookies)
        [self setCookie: cookie];
}

@end
