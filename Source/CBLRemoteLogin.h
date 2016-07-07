//
//  CBLRemoteLogin.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/8/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLRemoteSession;
@protocol CBLRemoteRequestDelegate, CBLAuthorizer;


NS_ASSUME_NONNULL_BEGIN

/** Logs into a server, asynchronously, using a CBLAuthorizer. */
@interface CBLRemoteLogin : NSObject

- (instancetype) initWithURL: (NSURL*)remoteURL
                   localUUID: (NSString*)localUUID
                     session: (CBLRemoteSession*)session
             requestDelegate: (nullable id<CBLRemoteRequestDelegate>)requestDelegate
                continuation: (void(^)(NSError* nullable))continuation NS_DESIGNATED_INITIALIZER;

- (instancetype) initWithURL: (NSURL*)remoteURL
                   localUUID: (NSString*)localUUID
                  authorizer: (nullable id<CBLAuthorizer>)authorizer
                continuation: (void(^)(NSError* nullable))continuation;

- (instancetype) init NS_UNAVAILABLE;

- (void) start;

@end

NS_ASSUME_NONNULL_END
