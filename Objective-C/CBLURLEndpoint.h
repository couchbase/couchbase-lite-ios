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

/** The URL object. */
@property (readonly, nonatomic) NSURL* url;

/**
 Initializes with the given URL. The supported URL schemes are ws and wss for
 transferring data over a secure connection.
 
 @param url The URL object.
 @return The CBLURLEndpoint object.
 */
- (instancetype) initWithURL: (NSURL*)url;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
