//
//  CBLRemoteSession.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/4/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLRemoteRequest, CBLCookieStorage;
@protocol CBLAuthorizer;


@interface CBLRemoteSession : NSObject

+ (NSURLSessionConfiguration*) defaultConfiguration;

- (instancetype) initWithConfiguration: (NSURLSessionConfiguration*)config
                            authorizer: (id<CBLAuthorizer>)authorizer
                         cookieStorage: (CBLCookieStorage*)cookieStorage;

- (instancetype) init;

@property (readonly) id<CBLAuthorizer> authorizer;

@property (readonly) NSArray<CBLRemoteRequest*>* activeRequests;

- (void) startRequest: (CBLRemoteRequest*)request;

- (void) stopActiveRequests;

- (void) close;

@end
