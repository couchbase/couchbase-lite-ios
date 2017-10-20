//
//  CBLQueryResult+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryResult.h"
#import "c4.h"
@class CBLQueryResultSet;

namespace fleeceapi {
    class MContext;
}

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryResult ()

- (instancetype) initWithResultSet: (CBLQueryResultSet*)rs
                      c4Enumerator: (C4QueryEnumerator*)e
                           context: (fleeceapi::MContext*)context;

@end

NS_ASSUME_NONNULL_END
