//
//  CBLClientCertAuthenticator.m
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

#import "CBLClientCertAuthenticator.h"
#import "MYAnonymousIdentity.h"

@implementation CBLClientCertAuthenticator
{
    NSString* _identityID;
}


- (instancetype) initWithIdentityID: (NSString*)identityID {
    CBLAssertNotNil(identityID);
    
    self = [super initWithNone];
    if (self) {
        _identityID = [identityID copy];
        SecIdentityRef identity = MYFindIdentity(_identityID);
        if (!identity)
            return nil;
        CFRelease(identity);
    }
    return self;
}


- (SecIdentityRef) identity {
    SecIdentityRef identity = MYFindIdentity(_identityID);
    if (identity)
        CFAutorelease(identity);
    return identity;
}


- (void) authenticate: (NSMutableDictionary *)options {
    NSMutableDictionary *auth = [NSMutableDictionary new];
    auth[@kC4ReplicatorAuthType] = @kC4AuthTypeClientCert;
    auth[@kC4ReplicatorAuthClientCert] = _identityID;
    options[@kC4ReplicatorOptionAuthentication] = auth;
}


@end
