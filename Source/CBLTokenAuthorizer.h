//
//  CBLTokenAuthorizer.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 4/11/14.
//  Copyright (c) 2014 Couchbase, Inc. All rights reserved.

#import "CBLAuthorizer.h"

/** Generic authorizer for services like Facebook and Persona where we need to POST a JSON
    request to a server endpoint (_facebook or _persona, respectively.) */
@interface CBLTokenAuthorizer : NSObject <CBLAuthorizer>

- (instancetype) initWithLoginPath: (NSString*)loginPath
                    postParameters: (NSDictionary*)params;

@end
