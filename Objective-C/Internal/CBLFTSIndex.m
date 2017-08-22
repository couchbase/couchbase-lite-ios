//
//  CBLFTSIndex.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFTSIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLQuery+Internal.h"

@implementation CBLFTSIndex {
    CBLFTSIndexItem* _item;
    CBLFTSIndexOptions* _options;
}

- (instancetype) initWithItems: (CBLFTSIndexItem*)item
                       options: (nullable CBLFTSIndexOptions*)options
{
    self = [super init];
    if (self) {
        _item = item;
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
    return @[[_item.expression asJSON]];
}

@end
