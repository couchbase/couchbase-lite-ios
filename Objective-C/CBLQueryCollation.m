//
//  CBLQueryCollation.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
