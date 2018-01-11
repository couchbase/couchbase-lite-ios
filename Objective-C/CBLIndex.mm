//
//  CBLIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryExpression.h"
#import "CBLValueIndex.h"
#import "CBLFullTextIndex.h"

@implementation CBLIndex

- (instancetype) initWithNone {
    return [super init];
}


+ (CBLValueIndex*) valueIndexWithItems: (NSArray<CBLValueIndexItem*>*)items {
    return [[CBLValueIndex alloc] initWithItems: items];
}


+ (CBLFullTextIndex*) fullTextIndexWithItems: (NSArray<CBLFullTextIndexItem*>*)items
                             options: (nullable CBLFullTextIndexOptions*)options
{
    return [[CBLFullTextIndex alloc] initWithItems: items options: options];
}


- (C4IndexType) indexType {
    // Implement by subclass
    return kC4ValueIndex;
}


- (C4IndexOptions) indexOptions {
    // Implement by subclass
    return (C4IndexOptions){ };
}


- (id) indexItems {
    return nil;
}


@end


@implementation CBLValueIndexItem

@synthesize expression=_expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}


+ (CBLValueIndexItem*) property: (NSString*)property{
    return [[CBLValueIndexItem alloc] initWithExpression:
            [CBLQueryExpression property: property]];
}


+ (CBLValueIndexItem*) expression: (CBLQueryExpression*)expression {
    return [[CBLValueIndexItem alloc] initWithExpression: expression];
}

@end


@implementation CBLFullTextIndexItem
            
@synthesize expression=_expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}

+ (CBLFullTextIndexItem*) property: (NSString*)property {
    return [[CBLFullTextIndexItem alloc] initWithExpression:
            [CBLQueryExpression property: property]];
}

@end


@implementation CBLFullTextIndexOptions

@synthesize locale=_locale, ignoreAccents=_ignoreAccents;

- (instancetype) init {
    return [super init];
}

@end
