//
//  CBLClientCertAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/23/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLAuthorizer.h"
#import <Security/Security.h>

@interface CBLClientCertAuthorizer : CBLAuthorizer <CBLCredentialAuthorizer>

- (instancetype) initWithIdentity: (SecIdentityRef)identity
                  supportingCerts: (NSArray*)certs;

@property (readonly) NSArray* certificateChain;

@end
