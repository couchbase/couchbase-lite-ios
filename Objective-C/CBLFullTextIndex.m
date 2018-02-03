//
//  CBLFullTextIndex.m
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

#import "CBLFullTextIndex.h"
#import "CBLIndex+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLFullTextIndex {
    NSArray<CBLFullTextIndexItem*>* _items;
}

@synthesize language=_language, ignoreAccents=_ignoreAccents;

- (instancetype) initWithItems: (NSArray<CBLFullTextIndexItem*>*)items {
    self = [super initWithNone];
    if (self) {
        _items = items;
        _language = [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
    }
    return self;
}


- (C4IndexType) indexType {
    return kC4FullTextIndex;
}


- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    if (_language)
        c4options.language = _language.UTF8String;
    c4options.ignoreDiacritics = _ignoreAccents;
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
