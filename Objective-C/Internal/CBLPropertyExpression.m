//
//  CBLPropertyExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLPropertyExpression.h"
#import "CBLQuery+Internal.h"

@implementation CBLPropertyExpression

@synthesize keyPath=_keyPath, columnName=_columnName, from=_from;

- (instancetype) initWithKeyPath: (NSString*)keyPath
                      columnName: (nullable NSString*)columnName
                            from: (NSString*)from {
    self = [super initWithNone];
    if (self) {
        _keyPath = keyPath;
        _columnName = columnName;
        _from = from;
    }
    return self;
}

- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    if ([_keyPath hasPrefix: @"rank("]) {
        [json addObject: @"rank()"];
        [json addObject: @[@".",
                           [_keyPath substringWithRange:
                            NSMakeRange(5, _keyPath.length - 6)]]];
    } else {
        if (_from)
            [json addObject: [NSString stringWithFormat: @".%@.%@", _from, _keyPath]];
        else
            [json addObject: [NSString stringWithFormat: @".%@", _keyPath]];
    }
    return json;
}

- (NSString*) columnName {
    if (!_columnName)
        _columnName = [_keyPath componentsSeparatedByString: @"."].lastObject;
    return _columnName;
}

@end
