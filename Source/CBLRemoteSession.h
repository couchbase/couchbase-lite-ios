//
//  CBLRemoteSession.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/4/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLRemoteRequest;


@interface CBLRemoteSession : NSObject

- (instancetype) initWithConfiguration: (NSURLSessionConfiguration*)config;

- (instancetype) init;

- (void) startRequest: (CBLRemoteRequest*)request;

- (void) close;

@end
