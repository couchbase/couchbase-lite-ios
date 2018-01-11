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
    NSString* locale = _options.locale;
    if (!locale)
        locale = [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
    
    C4IndexOptions c4options = { };
    c4options.language = locale.UTF8String;
    if (_options)
        c4options.ignoreDiacritics = _options.ignoreAccents;
    else
        c4options.ignoreDiacritics = [locale isEqualToString: @"en"];
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
