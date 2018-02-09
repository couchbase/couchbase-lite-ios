//
//  CBLValueIndex.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLValueIndex.h"
#import "CBLDatabase+Internal.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLValueIndex {
    NSArray<CBLValueIndexItem*>* _items;
}

- (instancetype) initWithItems: (NSArray<CBLValueIndexItem*>*)items {
    self = [super initWithNone];
    if (self) {
        _items = items;
    }
    return self;
}


- (C4IndexType) indexType {
    return kC4ValueIndex;
}


- (C4IndexOptions) indexOptions {
    return (C4IndexOptions){ };
}


- (id) indexItems {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: _items.count];
    for (CBLValueIndexItem* item in _items) {
        [json addObject: [item.expression asJSON]];
    }
    return json;
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
