//
//  CBLLiveQueryChange+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQueryChange.h"
@class CBLLiveQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLLiveQueryChange ()

- (instancetype) initWithQuery: (CBLLiveQuery*)query
                          rows: (nullable NSEnumerator<CBLQueryRow*>*)rows
                         error: (nullable NSError*)error;

@end

NS_ASSUME_NONNULL_END
