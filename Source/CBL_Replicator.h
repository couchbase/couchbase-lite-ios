//
//  CBL_Replicator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/6/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBL_ReplicatorAPI.h"

@class CBLBatcher;


@interface CBL_RESTReplicatorFactory : NSObject <CBL_ReplicatorFactory>
@end


/** Abstract base class for push or pull replications. */
@interface CBL_Replicator : NSObject <CBL_ReplicatorAPI>
{
    @protected
    CBLDatabase* __weak _db;
    NSURL* _remote;
    BOOL _continuous;
    NSString* _filterName;
    NSDictionary* _filterParameters;
    NSArray* _docIDs;
    NSString* _lastSequence;
    CBLBatcher* _batcher;
    id<CBLAuthorizer> _authorizer;
    NSDictionary* _options;
    NSDictionary* _requestHeaders;
    NSString* _serverType;
    CBLCookieStorage* _cookieStorage;
#if TARGET_OS_IPHONE
    NSUInteger /*UIBackgroundTaskIdentifier*/ _bgTask;
#endif
}

+ (NSString *)progressChangedNotification;
+ (NSString *)stoppedNotification;

/** Timeout interval for HTTP requests sent by this replicator.
    (Derived from options key "connection_timeout", in milliseconds.) */
@property (readonly) NSTimeInterval requestTimeout;

- (CBL_Revision *) transformRevision:(CBL_Revision *)rev;

@end
