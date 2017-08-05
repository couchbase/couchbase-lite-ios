//
//  CBLBasicAuthenticator.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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

@end

NS_ASSUME_NONNULL_END
