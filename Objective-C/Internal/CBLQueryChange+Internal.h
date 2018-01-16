//
//  CBLQueryChange+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryChange.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryChange ()

- (instancetype) initWithQuery: (CBLQuery*)query
                       results: (nullable CBLQueryResultSet*)results
                         error: (nullable NSError*)error;

@end

NS_ASSUME_NONNULL_END
