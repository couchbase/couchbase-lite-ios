//
//  CBLDatabase+Query.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/15/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#import "CBLPredicateQuery.h"


NS_ASSUME_NONNULL_BEGIN


@interface CBLDatabase (Query)

- (CBLPredicateQuery*) createQueryWhere: (nullable id)where;

@end


NS_ASSUME_NONNULL_END
