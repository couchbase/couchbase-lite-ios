//
//  CBLListener+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 7/7/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLListener.h"


UsingLogDomain(Listener);


@interface CBLListener ()

@property (readonly) NSArray* SSLIdentityAndCertificates;

@end
