//
//  CBLLiveQueryChange.h
//  CBL ObjC
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLLiveQuery;
@class CBLQueryRow;

NS_ASSUME_NONNULL_BEGIN

/** CBLLiveQueryChange contains the information about the query result changes reported
 by a live query object. */
@interface CBLLiveQueryChange : NSObject

/** The source live query object. */
@property (nonatomic, readonly) CBLLiveQuery* query;

/** The new query result. */
@property (nonatomic, readonly, nullable) NSEnumerator<CBLQueryRow*>* rows;

/** The error occurred when running the query. */
@property (nonatomic, readonly, nullable) NSError* error;

@end

NS_ASSUME_NONNULL_END
