//
//  CBLDatabase+NSPredicate.h
//  CBL ObjC
//
//  Created by Pasin Suriyentrakorn on 11/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"
@class CBLPredicateQuery;

NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabase ()

/**
 Compiles a database query, from any of several input formats.
 Once compiled, the query can be run many times with different parameter values.
 The rows will be sorted by ascending document ID, and no custom values are returned.
 
 @param where The query specification. This can be an NSPredicate, or an NSString (interpreted
 as an NSPredicate format string), or nil to return all documents.
 @return The CBLQuery.
 */
- (CBLPredicateQuery*) createQueryWhere: (nullable id)where;

@end

NS_ASSUME_NONNULL_END
