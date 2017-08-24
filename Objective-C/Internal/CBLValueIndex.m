//
//  CBLValueIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLValueIndex.h"
#import "CBLDatabase+Internal.h"
#import "CBLIndex+Internal.h"
#import "CBLQuery+Internal.h"

@implementation CBLValueIndex {
    NSArray<CBLValueIndexItem*>* _items;
}

- (instancetype) initWithItems: (NSArray<CBLValueIndexItem*>*)items {
    self = [super init];
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
