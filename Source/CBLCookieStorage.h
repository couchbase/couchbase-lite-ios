//
//  CBLCookieStorage.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/18/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class CBLDatabase;

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

/** Stores a cookie in the cookie storage */
- (void) setCookie: (NSHTTPCookie*)aCookie;

/** Deletes a specified cookie from the cookie storage. */
- (void) deleteCookie: (NSHTTPCookie*)aCookie;

/** Deletes all cookies from the cookie storage. */
- (void) deleteAllCookies;

/** Close the storage, clear reference to the database */
- (void) close;

@end
