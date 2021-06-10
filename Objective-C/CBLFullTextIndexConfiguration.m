//
//  CBLFullTextIndexConfiguration.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/9/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLFullTextIndexConfiguration.h"
#import "CBLIndexConfiguration+Internal.h"

@implementation CBLFullTextIndexConfiguration

@synthesize ignoreAccents=_ignoreAccents, language=_language;

- (instancetype) initWithExpression: (NSString*)expression
                      ignoreAccents: (BOOL)ignoreAccents
                           language: (NSString* __nullable)language {
    self = [super initWithIndexType: kC4FullTextIndex expression: expression];
    if (self) {
        _ignoreAccents = ignoreAccents;
        _language = language;
    }
    return self;
}

- (C4IndexOptions) indexOptions {
    C4IndexOptions c4options = { };
    if (_language)
        c4options.language = _language.UTF8String;
    c4options.ignoreDiacritics = _ignoreAccents;
    return c4options;
}

@end
