//
//  CBLLiveQuery+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQuery.h"
@class CBLQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLLiveQuery ()

- (instancetype) initWithQuery: (CBLQuery*)query;

@end

NS_ASSUME_NONNULL_END
