//
//  CBLRemoteSession.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/4/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
@class CBLCookieStorage;
@protocol CBLAuthorizer;


@interface CBLRemoteSession : NSObject

+ (NSURLSessionConfiguration*) defaultConfiguration;

- (instancetype) initWithConfiguration: (NSURLSessionConfiguration*)config
                               baseURL: (NSURL*)baseURL
                              delegate: (id<CBLRemoteRequestDelegate>)delegate
                            authorizer: (id<CBLAuthorizer>)authorizer
                         cookieStorage: (CBLCookieStorage*)cookieStorage;

- (instancetype) initWithDelegate: (id<CBLRemoteRequestDelegate>)delegate;

- (instancetype) init NS_UNAVAILABLE;

@property (readonly) id<CBLAuthorizer> authorizer;

@property (readonly) NSArray<CBLRemoteRequest*>* activeRequests;

- (void) startRequest: (CBLRemoteRequest*)request;

// convenience method
- (CBLRemoteJSONRequest*) startRequest: (NSString*)method
                                  path: (NSString*)path
                                  body: (id)body
                          onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

- (void) stopActiveRequests;

- (void) doAsync: (void (^)())block;

- (void) close;

@end
