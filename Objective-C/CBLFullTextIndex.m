//
//  CBLFTSIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFullTextIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLFullTextIndex {
    NSArray<CBLFullTextIndexItem*>* _items;
    CBLFullTextIndexOptions* _options;
}

- (instancetype) initWithItems: (NSArray<CBLFullTextIndexItem*>*)items
                       options: (nullable CBLFullTextIndexOptions*)options
{
    self = [super initWithNone];
    if (self) {
        _items = items;
        _options = options;
    }
    return self;
}


- (C4IndexType) indexType {
    return kC4FullTextIndex;
}


- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    if (_options) {
        c4options.language = _options.language.UTF8String;
        c4options.ignoreDiacritics = _options.ignoreAccents;
    }
    return c4options;
}


- (id) indexItems {
    NSMutableArray* json = [NSMutableArray arrayWithCapacity: _items.count];
    for (CBLFullTextIndexItem* item in _items) {
        [json addObject: [item.expression asJSON]];
    }
    return json;
}

@end
