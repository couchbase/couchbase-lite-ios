//
//  CBLQueryCollation.m
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

#import "CBLQueryCollation.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryCollation {
    BOOL _unicode;
    NSString* _locale;
    BOOL _ignoreCase;
    BOOL _ignoreAccents;
}


+ (CBLQueryCollation*) asciiWithIgnoreCase: (BOOL)ignoreCase {
    return [[CBLQueryCollation alloc] initWithUnicode: NO
                                               locale: nil
                                           ignoreCase: ignoreCase
                                        ignoreAccents: NO];
}


+ (CBLQueryCollation*) unicodeWithLocale: (nullable NSString*)locale
                              ignoreCase: (BOOL)ignoreCase
                           ignoreAccents: (BOOL)ignoreAccents
{
    return [[CBLQueryCollation alloc] initWithUnicode: YES
                                               locale: locale
                                           ignoreCase: ignoreCase
                                        ignoreAccents: ignoreAccents];
}


#pragma mark - Internal


- (instancetype) initWithUnicode: (BOOL)unicode
                          locale: (nullable NSString*)locale
                      ignoreCase: (BOOL)ignoreCase
                   ignoreAccents: (BOOL)ignoreAccents
{
    self = [super init];
    if (self) {
        _unicode = unicode;
        
        if (_unicode && !locale)
            locale = [NSLocale currentLocale].localeIdentifier;
        _locale = locale;
        
        _ignoreCase = ignoreCase;
        _ignoreAccents = ignoreAccents;
    }
    return self;
}


- (id) asJSON {
    return @{ @"UNICODE": @(_unicode),
              @"LOCALE": _locale ? _locale : [NSNull null],
              @"CASE": @(!_ignoreCase),
              @"DIAC": @(!_ignoreAccents)};
}

@end
