//
//  CookieStorage_Tests.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/20/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLCookieStorage.h"

#define $URL(urlStr)                            ([NSURL URLWithString: urlStr])
#define COMPARE_COOKIES(cookies1, cookies2)     [self compareCookies: cookies1 withCookies: cookies2]

@interface CookieStorage_Tests : CBLTestCaseWithDB

@end

@implementation CookieStorage_Tests
{
    CBLCookieStorage* _cookieStore;
    NSHTTPCookieStorage* _appleCookieStore;
}

- (void)setUp {
    [super setUp];
    _cookieStore = [[CBLCookieStorage alloc] initWithDB: db
                                             storageKey: @"cookie_store_unit_test"];
    _appleCookieStore = [NSHTTPCookieStorage sharedHTTPCookieStorage];
}

- (void)tearDown {
    [super tearDown];
    
    for (NSHTTPCookie *cookie in _appleCookieStore.cookies)
        [_appleCookieStore deleteCookie:cookie];
}

- (void) reloadCookieStore {
    _cookieStore = [[CBLCookieStorage alloc] initWithDB: db
                                             storageKey: @"cookie_store_unit_test"];
}

- (NSHTTPCookie*) cookie: (NSDictionary*)props {
    return [NSHTTPCookie cookieWithProperties:props];
}

- (void) addCookie2BothStores: (NSHTTPCookie*)cookie {
    [_cookieStore setCookie: cookie];
    [_appleCookieStore setCookie:cookie];
}

- (BOOL)compareCookies: (NSArray*)cookies1 withCookies: (NSArray*)cookies2 {
    // Expect no duplicate cookies in an array.
    if ([cookies1 count] != [cookies2 count])
        return NO;

    NSSet* cookie2Set = [NSSet setWithArray: cookies2];
    for (NSHTTPCookie* cookie in cookies1) {
        if (![cookie2Set containsObject: cookie])
            return NO;
    }
    return YES;
}

- (void) test_SetCookie_Persistent {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieComment: @"yummy",
                                             NSHTTPCookieCommentURL: @"www.mycookie.com",
                                             NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow:60.0],
                                             NSHTTPCookieVersion: @"0"
                            }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"darkchoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieComment: @"yummy",
                                             NSHTTPCookieCommentURL: @"www.mycookie.com",
                                             NSHTTPCookieMaximumAge: @(60),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie2];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);

    // Set cookie with same name, domain, and path
    // with one of the previously set cookies:
    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"darkchoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"bitter sweet",
                                             NSHTTPCookieComment: @"yummy",
                                             NSHTTPCookieCommentURL: @"www.mycookie.com",
                                             NSHTTPCookieMaximumAge: @(60),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie3];
    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie3);

    [self reloadCookieStore];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie3);
}

- (void) test_SetCookie_NameDomainPath {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/path",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie3];

    NSHTTPCookie* cookie4 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/path/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie4];

    NSHTTPCookie* cookie5 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @".mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie5];

    NSHTTPCookie* cookie6 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie6];

    NSHTTPCookie* cookie7 = [self cookie: @{ NSHTTPCookieName: @"cookie7",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie7];

    AssertEq(_cookieStore.cookies.count, 7u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);
    AssertEqual(_cookieStore.cookies[3], cookie4);
    AssertEqual(_cookieStore.cookies[4], cookie5);
    AssertEqual(_cookieStore.cookies[5], cookie6);
    AssertEqual(_cookieStore.cookies[6], cookie7);

    NSHTTPCookie* cookie8 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"bitter, sweet",
                                             }];
    [_cookieStore setCookie: cookie8];

    AssertEq(_cookieStore.cookies.count, 7u);
    AssertEqual(_cookieStore.cookies[0], cookie8);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);
    AssertEqual(_cookieStore.cookies[3], cookie4);
    AssertEqual(_cookieStore.cookies[4], cookie5);
    AssertEqual(_cookieStore.cookies[5], cookie6);
    AssertEqual(_cookieStore.cookies[6], cookie7);
}

- (void) test_SetCookie_SessionOnly {
    // No expires date specified for a cookie v0:
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"0"
                                             }];

    AssertNil(cookie1.expiresDate);
    [_cookieStore setCookie: cookie1];

    // No max age specified for a cookie v1:
    NSHTTPCookie *cookie2 = [self cookie: @{ NSHTTPCookieName: @"oatmeal_raisin",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"1"
                                             }];
    AssertNil(cookie2.expiresDate);
    [_cookieStore setCookie: cookie2];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);

    [self reloadCookieStore];

    // Sessions cookies are all discard:
    AssertEq(_cookieStore.cookies.count, 0u);
}


- (void) test_SetCookie_AcceptPolicy {
    _cookieStore.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet"
                                             }];
    [_cookieStore setCookie: cookie1];
    AssertEq(_cookieStore.cookies.count, 1u);
    AssertEqual(_cookieStore.cookies[0], cookie1);

    _cookieStore.cookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"oatmeal_raisin",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie2];
    AssertEq(_cookieStore.cookies.count, 1u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
}

- (void) test_DeleteCookie {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"oatmeal_raisin",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"darkchoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie3];

    AssertEq(_cookieStore.cookies.count, 3u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);

    [_cookieStore deleteCookie: cookie2];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie3);

    [self reloadCookieStore];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie3);

    [_cookieStore deleteCookie: cookie1];
    [_cookieStore deleteCookie: cookie3];

    AssertEq(_cookieStore.cookies.count, 0u);

    [self reloadCookieStore];

    AssertEq(_cookieStore.cookies.count, 0u);
}

- (void) test_DeleteCookiesByName {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"oatmeal_raisin",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"WhiteChoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/supersweet",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie3];

    AssertEq(_cookieStore.cookies.count, 3u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);

    [_cookieStore deleteCookiesNamed: @"WHITECHOCO"];
    AssertEq(_cookieStore.cookies.count, 3u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);

    [_cookieStore deleteCookiesNamed: @"whitechoco"];
    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie2);
    AssertEqual(_cookieStore.cookies[1], cookie3);

    [_cookieStore deleteCookiesNamed: @"WhiteChoco"];
    AssertEq(_cookieStore.cookies.count, 1u);
    AssertEqual(_cookieStore.cookies[0], cookie2);

    [self reloadCookieStore];

    AssertEq(_cookieStore.cookies.count, 1u);
    AssertEqual(_cookieStore.cookies[0], cookie2);
}

- (void) test_DeleteAllCookies {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"oatmeal_raisin",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"darkchoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(3600),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie3];

    AssertEq(_cookieStore.cookies.count, 3u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);
    AssertEqual(_cookieStore.cookies[2], cookie3);

    [_cookieStore deleteAllCookies];

    AssertEq(_cookieStore.cookies.count, 0u);

    [self reloadCookieStore];

    AssertEq(_cookieStore.cookies.count, 0u);
}

- (void) test_CookiesForURL {
    NSHTTPCookie* cookie00 = [self cookie: @{ NSHTTPCookieName: @"cookie00",
                                             NSHTTPCookieDomain: @"",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie00];

    NSHTTPCookie* cookie01 = [self cookie: @{ NSHTTPCookieName: @"cookie01",
                                              NSHTTPCookieDomain: @"",
                                              NSHTTPCookiePath: @"/",
                                              NSHTTPCookieValue: @"sweet",
                                              }];
    [self addCookie2BothStores: cookie01];

    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie2",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookie3",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie3];

    NSHTTPCookie* cookie4 = [self cookie: @{ NSHTTPCookieName: @"cookie4",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie4];

    NSHTTPCookie* cookie5 = [self cookie: @{ NSHTTPCookieName: @"cookie5",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning/specials",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie5];

    NSHTTPCookie* cookie6 = [self cookie: @{ NSHTTPCookieName: @"cookie6",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning/specials/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie6];

    NSHTTPCookie* cookie7 = [self cookie: @{ NSHTTPCookieName: @"cookie7",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie7];

    NSHTTPCookie* cookie8 = [self cookie: @{ NSHTTPCookieName: @"cookie8",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie8];

    NSHTTPCookie* cookie9 = [self cookie: @{ NSHTTPCookieName: @"cookie9",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/summer",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie9];

    NSHTTPCookie* cookie10 = [self cookie: @{ NSHTTPCookieName: @"cookie10",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/summer/specials",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie10];

    NSHTTPCookie* cookie11 = [self cookie: @{ NSHTTPCookieName: @"cookie10",
                                              NSHTTPCookieDomain: @"www.mycookie.com",
                                              NSHTTPCookiePath: @"summer",
                                              NSHTTPCookieValue: @"sweet",
                                              }];
    [self addCookie2BothStores: cookie11];

    NSHTTPCookie* cookie12 = [self cookie: @{ NSHTTPCookieName: @"cookie10",
                                              NSHTTPCookieDomain: @"www.mycookie.com",
                                              NSHTTPCookiePath: @"summer/specials",
                                              NSHTTPCookieValue: @"sweet",
                                              }];
    [self addCookie2BothStores: cookie12];

    NSArray* cookies1 = nil;
    NSArray* cookies2 = nil;
    NSURL* url = nil;

    url = $URL(@"http://mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://MyCookiE.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://MyCookiE.com/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 3u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/MorNinG");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/MorNinG/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/afternoon");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning/123");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning/specials");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 5u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    AssertEqual(cookies1[4], cookie5);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning/specials/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 6u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    AssertEqual(cookies1[4], cookie5);
    AssertEqual(cookies1[5], cookie6);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning/specials/123");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 6u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    AssertEqual(cookies1[4], cookie5);
    AssertEqual(cookies1[5], cookie6);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie7);
    AssertEqual(cookies1[1], cookie8);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/summer");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 3u);
    AssertEqual(cookies1[0], cookie7);
    AssertEqual(cookies1[1], cookie8);
    AssertEqual(cookies1[2], cookie9);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/summer/");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 3u);
    AssertEqual(cookies1[0], cookie7);
    AssertEqual(cookies1[1], cookie8);
    AssertEqual(cookies1[2], cookie9);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/summer/specials");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie7);
    AssertEqual(cookies1[1], cookie8);
    AssertEqual(cookies1[2], cookie9);
    AssertEqual(cookies1[3], cookie10);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://notmycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 0u);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.notmycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 0u);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www2.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 0u);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www2.mycookie.com/summer");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 0u);
    Assert(COMPARE_COOKIES(cookies1, cookies2));
}

- (void) test_CookiesForURL_DomainCookies {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @".mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie2",
                                             NSHTTPCookieDomain: @".mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookie3",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie3];

    NSHTTPCookie* cookie4 = [self cookie: @{ NSHTTPCookieName: @"cookie4",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie4];

    NSHTTPCookie* cookie5 = [self cookie: @{ NSHTTPCookieName: @"cookie5",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie5];

    NSHTTPCookie* cookie6 = [self cookie: @{ NSHTTPCookieName: @"cookie6",
                                             NSHTTPCookieDomain: @".www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie6];

    NSHTTPCookie* cookie7 = [self cookie: @{ NSHTTPCookieName: @"cookie7",
                                             NSHTTPCookieDomain: @".www.mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie7];

    NSHTTPCookie* cookie8 = [self cookie: @{ NSHTTPCookieName: @"cookie8",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie8];

    NSHTTPCookie* cookie9 = [self cookie: @{ NSHTTPCookieName: @"cookie9",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [self addCookie2BothStores: cookie9];

    NSArray* cookies1 = nil;
    NSArray* cookies2 = nil;
    NSURL* url = nil;

    url = $URL(@"http://mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://MyCooKie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie.com/morning");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 5u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    AssertEqual(cookies1[4], cookie5);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie6);
    AssertEqual(cookies1[3], cookie8);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/morning");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 6u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie6);
    AssertEqual(cookies1[3], cookie7);
    AssertEqual(cookies1[4], cookie8);
    AssertEqual(cookies1[5], cookie9);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/morning/123");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 6u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie6);
    AssertEqual(cookies1[3], cookie7);
    AssertEqual(cookies1[4], cookie8);
    AssertEqual(cookies1[5], cookie9);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www2.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www2.MyCooKie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://sub1.sub2.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://mycookie2.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 0u);
    Assert(COMPARE_COOKIES(cookies1, cookies2));
}

- (void) test_CookiesForURL_Secure {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieSecure: @"TRUE"
                                             }];
    [self addCookie2BothStores: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie2",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet"
                                             }];
    [self addCookie2BothStores: cookie2];

    Assert(cookie1.isSecure);
    Assert(!cookie2.isSecure);

    NSArray* cookies1 = nil;
    NSArray* cookies2 = nil;
    NSURL* url = nil;

    // Get only matched non-secure cookies:
    url = $URL(@"http://www.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 1u);
    AssertEqual(cookies1[0], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    // Get both matched secure and non-secure cookies:
    url = $URL(@"https://www.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 2u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    Assert(COMPARE_COOKIES(cookies1, cookies2));
}

- (void) test_CookiesForURL_Ports {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [self addCookie2BothStores: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie2",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookiePort: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [self addCookie2BothStores: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookie3",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookiePort: @"4984",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [self addCookie2BothStores: cookie3];

    NSHTTPCookie* cookie4 = [self cookie: @{ NSHTTPCookieName: @"cookie4",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookiePort: @"4984",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [self addCookie2BothStores: cookie4];

    NSHTTPCookie* cookie5 = [self cookie: @{ NSHTTPCookieName: @"cookie5",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookiePort: @"4984",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieVersion: @"0"
                                             }];
    [self addCookie2BothStores: cookie5];

    NSArray* cookies1 = nil;
    NSArray* cookies2 = nil;
    NSURL* url = nil;

    cookies1 = _cookieStore.cookies;
    cookies2 = _appleCookieStore.cookies;
    AssertEq(cookies1.count, 5u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie2);
    AssertEqual(cookies1[2], cookie3);
    AssertEqual(cookies1[3], cookie4);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    // Setting to an empty string ("") currently results to a port number 0 (SDK BUG).
    // As a result, only one cookie will be returned here instead of two.
    // https://developer.apple.com/library/ios/documentation/Cocoa/Reference/Foundation/Classes/NSHTTPCookie_Class/index.html
    url = $URL(@"http://www.mycookie.com");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 1u);
    AssertEqual(cookies1[0], cookie1);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    // Setting NSHTTPCookiePort also has effect on cookies version 0, which is different
    // from what is being said the apple document. We are maintaining the same behavior here.
    url = $URL(@"http://www.mycookie.com:4984");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 3u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie3);
    AssertEqual(cookies1[2], cookie5);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com/morning");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 1u);
    AssertEqual(cookies1[0], cookie1);
    Assert(COMPARE_COOKIES(cookies1, cookies2));

    url = $URL(@"http://www.mycookie.com:4984/morning");
    cookies1 = [_cookieStore cookiesForURL: url];
    cookies2 = [_appleCookieStore cookiesForURL: url];
    AssertEq(cookies1.count, 4u);
    AssertEqual(cookies1[0], cookie1);
    AssertEqual(cookies1[1], cookie3);
    AssertEqual(cookies1[2], cookie4);
    AssertEqual(cookies1[3], cookie5);
    Assert(COMPARE_COOKIES(cookies1, cookies2));
}

- (void) test_CookiesEscapedURL {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookie1",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookie2",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/with%20space",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookie3",
                                             NSHTTPCookieDomain: @"www.mycookie.com",
                                             NSHTTPCookiePath: @"/with%20space/123",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie3];

    NSArray* cookies = nil;

    cookies = [_cookieStore cookiesForURL: $URL(@"http://www.mycookie.com")];
    AssertEq(cookies.count, 1u);
    AssertEqual(cookies[0], cookie1);

    cookies = [_cookieStore cookiesForURL: $URL(@"http://www.mycookie.com/with%20space")];
    AssertEq(cookies.count, 2u);
    AssertEqual(cookies[0], cookie1);
    AssertEqual(cookies[1], cookie2);

    cookies = [_cookieStore cookiesForURL: $URL(@"http://www.mycookie.com/with%20space/123")];
    AssertEq(cookies.count, 3u);
    AssertEqual(cookies[0], cookie1);
    AssertEqual(cookies[1], cookie2);
    AssertEqual(cookies[2], cookie3);
}


- (void) test_CookieExpires {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"whitechoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieExpires: [NSDate dateWithTimeIntervalSinceNow: 1.0],
                                             NSHTTPCookieVersion: @"0"
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"darkchoco",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             NSHTTPCookieMaximumAge: @(1.0),
                                             NSHTTPCookieVersion: @"1"
                                             }];
    [_cookieStore setCookie: cookie2];

    AssertEq(_cookieStore.cookies.count, 2u);
    AssertEqual(_cookieStore.cookies[0], cookie1);
    AssertEqual(_cookieStore.cookies[1], cookie2);

    [NSThread sleepForTimeInterval: 1.5];

    AssertEq(_cookieStore.cookies.count, 0u);
}

- (void) test_SortedCookies {
    NSHTTPCookie* cookie1 = [self cookie: @{ NSHTTPCookieName: @"cookieB",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie1];

    NSHTTPCookie* cookie2 = [self cookie: @{ NSHTTPCookieName: @"cookieA",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie2];

    NSHTTPCookie* cookie3 = [self cookie: @{ NSHTTPCookieName: @"cookieD",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie3];

    NSHTTPCookie* cookie4 = [self cookie: @{ NSHTTPCookieName: @"cookieC",
                                             NSHTTPCookieDomain: @"mycookie.com",
                                             NSHTTPCookiePath: @"/morning/",
                                             NSHTTPCookieValue: @"sweet",
                                             }];
    [_cookieStore setCookie: cookie4];

    NSArray* cookies = nil;

    cookies = _cookieStore.cookies;
    AssertEq(cookies.count, 4u);
    AssertEqual(cookies[0], cookie1);
    AssertEqual(cookies[1], cookie2);
    AssertEqual(cookies[2], cookie3);
    AssertEqual(cookies[3], cookie4);

    NSSortDescriptor *nameAsc = [[NSSortDescriptor alloc] initWithKey: @"name" ascending: YES];
    cookies = [_cookieStore sortedCookiesUsingDescriptors: @[nameAsc]];
    AssertEq(cookies.count, 4u);
    AssertEqual(cookies[0], cookie2);
    AssertEqual(cookies[1], cookie1);
    AssertEqual(cookies[2], cookie4);
    AssertEqual(cookies[3], cookie3);

    NSSortDescriptor *nameDesc = [[NSSortDescriptor alloc] initWithKey: @"name" ascending: NO];
    cookies = [_cookieStore sortedCookiesUsingDescriptors: @[nameDesc]];
    AssertEq(cookies.count, 4u);
    AssertEqual(cookies[0], cookie3);
    AssertEqual(cookies[1], cookie4);
    AssertEqual(cookies[2], cookie1);
    AssertEqual(cookies[3], cookie2);
}

@end
