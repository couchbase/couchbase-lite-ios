//
//  CBLQueryJoin.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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


+ (instancetype) join: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression {
    return [[self alloc] initWithType: kCBLInnerJoin dataSource: dataSource on: expression];
}


+ (instancetype) leftJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression {
    return [[self alloc] initWithType: kCBLLeftOuterJoin dataSource: dataSource on: expression];
}


+ (instancetype) leftOuterJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression {
    return [[self alloc] initWithType: kCBLLeftOuterJoin dataSource: dataSource on: expression];
}


+ (instancetype) innerJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression {
    return [[self alloc] initWithType: kCBLInnerJoin dataSource: dataSource on: expression];
}


+ (instancetype) crossJoin: (CBLQueryDataSource*)dataSource on: (CBLQueryExpression*)expression {
    return [[self alloc] initWithType: kCBLCrossJoin dataSource: dataSource on: expression];
}


#pragma mark - Internal


- (instancetype) initWithType: (NSString*)type
                   dataSource: (CBLQueryDataSource*)dataSource
                           on: (CBLQueryExpression*)expression
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
