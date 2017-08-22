//
//  CBLFTSIndex.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLIndex.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFTSIndex : CBLIndex

- (instancetype) initWithItems: (CBLFTSIndexItem*)item
                       options: (nullable CBLFTSIndexOptions*)options;

@end

NS_ASSUME_NONNULL_END
