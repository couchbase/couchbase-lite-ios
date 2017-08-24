//
//  CBLIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLValueIndex.h"
#import "CBLFTSIndex.h"

@implementation CBLIndex


+ (CBLIndex*) valueIndexOn: (NSArray<CBLValueIndexItem*>*)items {
    return [[CBLValueIndex alloc] initWithItems: items];
}


+ (CBLIndex*) ftsIndexOn: (CBLFTSIndexItem*)item options: (nullable CBLFTSIndexOptions*)options {
    return [[CBLFTSIndex alloc] initWithItems: item options: options];
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

+ (CBLValueIndexItem*) expression: (CBLQueryExpression*)expression {
    return [[CBLValueIndexItem alloc] initWithExpression: expression];
}

@end


@implementation CBLFTSIndexItem
            
@synthesize expression=_expression;

- (instancetype) initWithExpression: (CBLQueryExpression*)expression {
    self = [super init];
    if (self) {
        _expression = expression;
    }
    return self;
}

+ (CBLFTSIndexItem*) expression: (CBLQueryExpression*)expression {
    return [[CBLFTSIndexItem alloc] initWithExpression: expression];
}

@end


@implementation CBLFTSIndexOptions

@synthesize locale=_locale, ignoreAccents=_ignoreAccents;

- (instancetype) init {
    return [super init];
}

@end
