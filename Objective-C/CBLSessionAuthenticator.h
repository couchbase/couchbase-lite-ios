//
//  CBLSessionAuthenticator.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
