//
//  CBLValueIndex.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLIndex.h"
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLValueIndex: CBLIndex

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

/**
 Value Index Item.
 */
@interface CBLValueIndexItem: NSObject

/**
 Creates a value index item with the given property name.
 
 @param property The property name
 @return The value index item;
 */
+ (CBLValueIndexItem*) property: (NSString*)property;

/**
 Creates a value index item with the given expression.
 
 @param expression The expression to index. Typically a property expression.
 @return The value index item.
 */
+ (CBLValueIndexItem*) expression: (CBLQueryExpression*)expression;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
