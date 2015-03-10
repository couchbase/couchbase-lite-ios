//
//  CBLCookieStorage.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/18/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLDatabase;

/** NSNotification posted when the cookies stored in the CBLCookieStorage instance have changed. 
    The notification does not contain a userInfo dictionary */
extern NSString* const CBLCookieStorageCookiesChangedNotification;

@interface CBLCookieStorage : NSObject

/** All cookies that haven't been expired. */
@property(readonly, copy) NSArray* cookies;

/** The cookie storage’s cookie accept policy. 
    Currently support NSHTTPCookieAcceptPolicyAlways (Default) and NSHTTPCookieAcceptPolicyNever. */
@property NSHTTPCookieAcceptPolicy cookieAcceptPolicy;

/** Creates a cookie storage that will store cookies inside the given database as a local document 
    referenced by a unique storage key. */
- (instancetype) initWithDB: (CBLDatabase*)db storageKey: (NSString*)storageKey;

/** Returns an array of cookies that match with the given url. */
- (NSArray*) cookiesForURL: (NSURL*)theURL;

/** Returns an array of cookies orted according to a given set of sort descriptors. */
- (NSArray*) sortedCookiesUsingDescriptors: (NSArray*)sortOrder;

/** Stores a cookie in the cookie storage. */
- (void) setCookie: (NSHTTPCookie*)aCookie;

/** Deletes a specified cookie from the cookie storage. */
- (void) deleteCookie: (NSHTTPCookie*)aCookie;

/** Deletes all cookies by name case-sensitively. */
- (void) deleteCookiesNamed: (NSString*)name;

/** Deletes all cookies from the cookie storage. */
- (void) deleteAllCookies;

@end


@interface CBLCookieStorage (NSURLRequestResponse)

- (void) addCookieHeaderToRequest: (NSMutableURLRequest*)request;

- (void) setCookieFromResponse: (NSHTTPURLResponse*)response;

@end