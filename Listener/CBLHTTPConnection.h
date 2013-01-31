//
//  CBLHTTPConnection.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPConnection.h"
@class CBLListener;


@interface CBLHTTPConnection : HTTPConnection

@property (readonly) CBLListener* listener;

@end
