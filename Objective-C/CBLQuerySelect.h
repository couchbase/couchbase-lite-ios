//
//  CBLQuerySelect.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/** A CBLQuerySelect represents the returning properties in each query result row. */
@interface CBLQuerySelect : NSObject

/** Construct CBLQuerySelect that represents all properties. 
    @return a CBLQuerySelect representing all properties. */
+ (CBLQuerySelect*) all;

@end

NS_ASSUME_NONNULL_END
