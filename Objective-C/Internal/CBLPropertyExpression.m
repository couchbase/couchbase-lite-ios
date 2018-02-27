//
//  CBLPropertyExpression.m
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

#import "CBLPropertyExpression.h"
#import "CBLQueryExpression+Internal.h"

NSString* const kCBLAllPropertiesName = @"";

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
