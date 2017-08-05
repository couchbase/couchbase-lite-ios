//
//  CBLQueryResultSet.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/18/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLQueryResult;

/** 
 CBLQueryResultSet is a result returned from a query. The CBLQueryResultSet is an NSEnumerator of
 the CBLQueryResult objects, each of which represent a single row in the query result.
 */
@interface CBLQueryResultSet : NSEnumerator<CBLQueryResult*>

@end
