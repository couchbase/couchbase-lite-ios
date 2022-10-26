//
//  CBLFullTextIndexConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

#import "CBLFullTextIndexConfiguration.h"
#import "CBLIndexConfiguration+Internal.h"

@implementation CBLFullTextIndexConfiguration

@synthesize ignoreAccents=_ignoreAccents, language=_language;

- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions
                      ignoreAccents: (BOOL)ignoreAccents
                           language: (NSString* __nullable)language {
    self = [super initWithIndexType: kC4FullTextIndex expressions: expressions];
    if (self) {
        // there is no default 'ignoreAccents', since its NOT an optional argument.
        _ignoreAccents = ignoreAccents;
        _language = language;
    }
    return self;
}

- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    
    if (!_language)
        _language = [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
    c4options.language = _language.UTF8String;
    
    c4options.ignoreDiacritics = _ignoreAccents;
    return c4options;
}

@end
