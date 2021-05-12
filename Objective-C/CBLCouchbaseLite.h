//
//  CBLCouchbaseLite.h
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 4/24/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLLog;

NS_ASSUME_NONNULL_BEGIN

@interface CBLCouchbaseLite : NSObject

/**
 Log object used for configuring console, file, and custom logger.

 @return log object
 */
+ (CBLLog*) log;

@end

NS_ASSUME_NONNULL_END
