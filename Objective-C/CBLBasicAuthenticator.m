//
//  CBLBasicAuthenticator.m
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

#import "CBLBasicAuthenticator.h"
#import "CBLAuthenticator+Internal.h"

@implementation CBLBasicAuthenticator

@synthesize username=_username, password=_password;


- (instancetype) initWithUsername: (NSString*)username password: (NSString*)password {
    self = [super initWithNone];
    if (self) {
        _username = username;
        _password = password;
    }
    return self;
}


- (void) authenticate: (NSMutableDictionary *)options {
    NSMutableDictionary *auth = [NSMutableDictionary new];
    auth[@kC4ReplicatorAuthType] = @kC4AuthTypeBasic;
    auth[@kC4ReplicatorAuthUserName] = _username;
    auth[@kC4ReplicatorAuthPassword] = _password;
    options[@kC4ReplicatorOptionAuthentication] = auth;
}


@end
