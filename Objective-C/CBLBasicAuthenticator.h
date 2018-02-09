//
//  CBLBasicAuthenticator.h
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
 The CBLBasicAuthenticator class is an authenticator that will authenticate using HTTP Basic
 auth with the given username and password. This should only be used over an SSL/TLS connection,
 as otherwise it's very easy for anyone sniffing network traffic to read the password.
 */
@interface CBLBasicAuthenticator : CBLAuthenticator

/** The username set to the CBLBasicAuthenticator. */
@property (readonly, copy, nonatomic) NSString* username;

/** The password set to the CBLBasicAuthenticator. */
@property (readonly, copy, nonatomic) NSString* password;

/** Initializes the CBLBasicAuthenticator with the given username and password. */
- (instancetype) initWithUsername: (NSString*)username password: (NSString*)password;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
