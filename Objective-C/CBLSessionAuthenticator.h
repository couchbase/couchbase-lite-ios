//
//  CBLSessionAuthenticator.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLAuthenticator.h"

NS_ASSUME_NONNULL_BEGIN

/** 
 The CBLSessionAuthenticator class is an authenticator that will authenticate
 by using the session ID of the session created by a Sync Gateway.
 */
@interface CBLSessionAuthenticator : CBLAuthenticator

/** Session ID of the session created by a Sync Gateway. */
@property (nonatomic, readonly, copy) NSString* sessionID;

/** 
 Session cookie name that the session ID value will be set to when communicating
 the Sync Gateaway.
 */
@property (nonatomic, readonly, copy) NSString* cookieName;


/**
 Initializes with the Sync Gateway session ID and uses the default cookie name.

 @param sessionID Sync Gateway session ID
 @return The CBLSessionAuthenticator object.
 */
- (instancetype) initWithSessionID: (NSString*)sessionID;


/**
 Initializes with the session ID and the cookie name. If the given cookieName
 is nil, the default cookie name will be used.

 @param sessionID Sync Gateway session ID
 @param cookieName The cookie name
 @return The CBLSessionAuthenticator object.
 */
- (instancetype) initWithSessionID: (NSString*)sessionID
                        cookieName: (nullable NSString*)cookieName;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
