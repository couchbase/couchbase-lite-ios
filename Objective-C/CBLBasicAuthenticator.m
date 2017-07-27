//
//  CBLBasicAuthenticator.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLBasicAuthenticator.h"
#import "CBLAuthenticator+Internal.h"

@implementation CBLBasicAuthenticator

@synthesize username=_username, password=_password;


- (instancetype) initWithUsername: (NSString*)username password: (NSString*)password {
    self = [super init];
    if (self) {
        _username = username;
        _password = password;
    }
    return self;
}


- (void) authenticate: (NSMutableDictionary *)options {
    NSMutableDictionary *auth = [NSMutableDictionary new];
    auth[@kC4ReplicatorAuthType] = @kC4ReplicatorAuthPassword;
    auth[@kC4ReplicatorAuthUserName] = _username;
    auth[@kC4ReplicatorAuthPassword] = _password;
    options[@kC4ReplicatorOptionAuthentication] = auth;
}


@end
