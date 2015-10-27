//
//  CBLRemoteLogging.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 11/2/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTimeSeries.h"

#define kCBLRemoteLogDocType @"CBLRemoteLog"


NS_ASSUME_NONNULL_BEGIN

@interface CBLRemoteLogging : CBLTimeSeries

+ (nullable instancetype) sharedInstance;

- (void) enableLogging: (NSArray*)types;

@end

NS_ASSUME_NONNULL_END
