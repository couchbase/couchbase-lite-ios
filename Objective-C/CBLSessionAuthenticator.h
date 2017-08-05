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
 The CBLSessionAuthenticator class is an authenticator that will authenticate by using the
 session ID of the session created by a Sync Gateway.
 */
@interface CBLSessionAuthenticator : CBLAuthenticator

/** Session ID of the session created by a Sync Gateway. */
@property (nonatomic, readonly, copy) NSString* sessionID;

/** Session expiration date. */
@property (nonatomic, readonly, copy, nullable) NSDate* expires;

/** 
 Session cookie name that the session ID value will be set to when communicating
 the Sync Gateaway.
 */
@property (nonatomic, readonly, copy) NSString* cookieName;

/** 
 Initiallize the CBLSessionAuthenticator with the given session ID, expiration date,
 and cookie name.
 */
- (instancetype) initWithSessionID: (NSString*)sessionID
                           expires: (nullable id)expires
                        cookieName: (NSString*)cookieName;

@end

NS_ASSUME_NONNULL_END
