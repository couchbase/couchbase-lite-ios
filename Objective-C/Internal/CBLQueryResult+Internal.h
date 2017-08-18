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

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryResult ()

@property (nonatomic, readonly) CBLDatabase* database;

- (instancetype) initWithResultSet: (CBLQueryResultSet*)rs
                      c4Enumerator: (C4QueryEnumerator*)e;

@end

NS_ASSUME_NONNULL_END
