//
//  CBLURLEndpoint.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLEndpoint.h"

NS_ASSUME_NONNULL_BEGIN

/**
 URL based replication target endpoint.
 */
@interface CBLURLEndpoint : NSObject <CBLEndpoint>

/**
 Initializes with the host and the secure flag.
 
 @param host The URL host.
 @param secure The secure flag indicating whether the replication data will be
               sent over secure channels.
 @return The CBLURLEndpoint object.
 */
- (instancetype) initWithHost: (NSString*)host secure: (BOOL)secure;

/**
 Initializes with the host, the path, and the secure flag.

 @param host The URL host.
 @param path The URL path.
 @param secure The secure flag indicating whether the replication data will be
               sent over secure channels.
 @return The CBLURLEndpoint object.
 */
- (instancetype) initWithHost: (NSString*)host
                         path: (nullable NSString*)path
                       secure: (BOOL)secure;


/**
 Initializes with the host, the port, the path, and the secure flag.

 @param host The URL host.
 @param port The URL port number. If the port is not present,
             set the value to -1.
 @param path The URL path.
 @param secure The secure flag indicating whether the replication data will be
               sent over secure channels.
 @return The CBLURLEndpoint object.
 */
- (instancetype) initWithHost: (NSString*)host
                         port: (NSInteger)port
                         path: (nullable NSString*)path
                       secure: (BOOL)secure;

/** The URL host. */
@property (readonly, nonatomic) NSString* host;

/** The URL port. */
@property (readonly, nonatomic) NSInteger port;

/** The URL path. */
@property (readonly, nonatomic, nullable) NSString* path;

/**
 A boolean value indicates whether the replication data will be sent over
 secure channels.
 */
@property (readonly, nonatomic, getter=isSecure) BOOL secure;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
