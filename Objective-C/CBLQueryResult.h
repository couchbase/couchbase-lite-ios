//
//  CBLQueryResult.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlyDictionary.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryResult : NSObject <CBLReadOnlyArray, CBLReadOnlyDictionary>

/** Not Available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
