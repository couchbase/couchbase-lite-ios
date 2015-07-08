//
//  CBLHTTPResponse.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "HTTPResponse.h"
@class CBLHTTPConnection, CBL_Router;


@interface CBLHTTPResponse : NSObject <HTTPResponse>

- (instancetype) initWithRouter: (CBL_Router*)router forConnection:(CBLHTTPConnection*)connection;

@property UInt64 offset;

@end
