//
//  CBLClientCertAuthenticator.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/27/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLClientCertAuthenticator.h"
#import "MYAnonymousIdentity.h"

@implementation CBLClientCertAuthenticator
{
    NSString* _identityID;
}


- (instancetype) initWithIdentityID: (NSString*)identityID {
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
