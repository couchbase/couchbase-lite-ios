//
//  CBLQueryResultSet+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryResultSet.h"
#import "c4.h"
@class CBLDatabase, CBLQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryResultSet ()

- (instancetype) initWithQuery: (CBLQuery*)query
                       c4Query: (C4Query*)c4Query
                    enumerator: (C4QueryEnumerator*)e
                   columnNames: (NSDictionary*)columnNames;

@property (nonatomic, weak, readonly) CBLDatabase* database;
@property (nonatomic, readonly) C4Query* c4Query;
@property (nonatomic, readonly) NSDictionary* columnNames;

- (id) objectAtIndex: (NSUInteger)index;

// If query results have changed, returns a new enumerator, else nil.
- (nullable CBLQueryResultSet*) refresh: (NSError**)outError;

@end

NS_ASSUME_NONNULL_END
