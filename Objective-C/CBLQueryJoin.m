//
//  CBLQueryJoin.m
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

#import "CBLQueryJoin.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression+Internal.h"

#define kCBLInnerJoin       @"INNER"
#define kCBLOuterJoin       @"OUTER"
#define kCBLLeftOuterJoin   @"LEFT OUTER"
#define kCBLCrossJoin       @"CROSS"

@implementation CBLQueryJoin {
    NSString* _type;
    CBLQueryDataSource* _dataSource;
    CBLQueryExpression* _on;
}


+ (instancetype) join: (CBLQueryDataSource*)dataSource
                   on: (nullable CBLQueryExpression*)expression
{
    CBLAssertNotNil(dataSource);
    
    return [[self alloc] initWithType: kCBLInnerJoin dataSource: dataSource on: expression];
}


+ (instancetype) leftJoin: (CBLQueryDataSource*)dataSource
                       on: (nullable CBLQueryExpression*)expression
{
    CBLAssertNotNil(dataSource);
    
    return [[self alloc] initWithType: kCBLLeftOuterJoin dataSource: dataSource on: expression];
}


+ (instancetype) leftOuterJoin: (CBLQueryDataSource*)dataSource
                            on: (nullable CBLQueryExpression*)expression
{
    CBLAssertNotNil(dataSource);
    
    return [[self alloc] initWithType: kCBLLeftOuterJoin dataSource: dataSource on: expression];
}


+ (instancetype) innerJoin: (CBLQueryDataSource*)dataSource
                        on: (nullable CBLQueryExpression*)expression
{
    CBLAssertNotNil(dataSource);
    
    return [[self alloc] initWithType: kCBLInnerJoin dataSource: dataSource on: expression];
}


+ (instancetype) crossJoin: (CBLQueryDataSource*)dataSource {
    CBLAssertNotNil(dataSource);
    
    return [[self alloc] initWithType: kCBLCrossJoin dataSource: dataSource on: nil];
}


#pragma mark - Internal


- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (nullable CBLQueryExpression*)expression
{
    self = [super init];
    if (self) {
        _type = type;
        _dataSource = dataSource;
        _on = expression;
    }
    return self;
}


- (id) asJSON {
    NSMutableDictionary* json = [NSMutableDictionary new];
    json[@"JOIN"] = _type;
    json[@"ON"] = [_on asJSON];
    [json addEntriesFromDictionary: [_dataSource asJSON]];
    return json;
}


@end
