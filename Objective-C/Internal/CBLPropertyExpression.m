//
//  CBLPropertyExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/1/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLPropertyExpression.h"
#import "CBLQuery+Internal.h"

NSString* kCBLAllPropertiesName = @"";

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


+ (instancetype) allFrom: (nullable NSString*)from {
    // Use data source alias name as the column name if specified:
    NSString* colName = from ? from : kCBLAllPropertiesName;
    return [[self alloc] initWithKeyPath: kCBLAllPropertiesName columnName: colName from: from];
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    if (_from)
        [json addObject: [NSString stringWithFormat: @".%@.%@", _from, _keyPath]];
    else
        [json addObject: [NSString stringWithFormat: @".%@", _keyPath]];
    return json;
}


- (NSString*) columnName {
    if (!_columnName)
        _columnName = [_keyPath componentsSeparatedByString: @"."].lastObject;
    return _columnName;
}

@end
