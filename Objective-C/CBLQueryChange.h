//
//  CBLQueryChange.h
//  CBL ObjC
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQuery;
@class CBLQueryResultSet;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryChange contains the information about the query result changes reported
 by a live query object.
 */
@interface CBLQueryChange : NSObject

/** The source live query object. */
@property (nonatomic, readonly) CBLQuery* query;

/** The new query result. */
@property (nonatomic, readonly, nullable) CBLQueryResultSet* results;

/** The error occurred when running the query. */
@property (nonatomic, readonly, nullable) NSError* error;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
