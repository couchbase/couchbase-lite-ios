//
//  CBLIndex.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/30/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 CBLIndex represents an index which could be a value index for regular queries or
 full-text index for full-text queries (using the match operator).
 */
@interface CBLIndex : NSObject

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
