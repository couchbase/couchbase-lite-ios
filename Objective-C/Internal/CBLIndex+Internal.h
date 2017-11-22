//
//  CBLIndex+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "c4.h"
#import "CBLIndex.h"
#import "CBLFullTextIndex.h"
#import "CBLValueIndex.h"
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

@interface CBLIndex ()

@property (readonly) C4IndexType indexType;

@property (readonly) C4IndexOptions indexOptions;

@property (readonly, nullable) id indexItems;

@end

@interface CBLFullTextIndex ()

- (instancetype) initWithItems: (NSArray<CBLFullTextIndexItem*>*)items
                       options: (nullable CBLFullTextIndexOptions*)options;

@end

@interface CBLValueIndex ()

- (instancetype) initWithItems: (NSArray<CBLValueIndexItem*>*)items;

@end

@interface CBLValueIndexItem ()

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

@interface CBLFullTextIndexItem ()

@property (nonatomic, readonly) CBLQueryExpression* expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression;

@end

NS_ASSUME_NONNULL_END
