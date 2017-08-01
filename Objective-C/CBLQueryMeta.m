//
//  CBLQueryMeta.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryMeta.h"
#import "CBLQuery+Internal.h"
#import "CBLPropertyExpression.h"

#define kCBLQueryMetaIDKeyPath @"_id"
#define kCBLQueryMetaIDColumnName @"id"

#define kCBLQueryMetaSequenceKeyPath @"_sequence"
#define kCBLQueryMetaSequenceColumnName @"sequence"

@implementation CBLQueryMeta {
    NSString* _alias;
}


- (CBLQueryExpression*) id {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaIDKeyPath
                                               columnName: kCBLQueryMetaIDColumnName
                                                     from: _alias];
}


- (CBLQueryExpression*) sequence {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaSequenceKeyPath
                                               columnName: kCBLQueryMetaSequenceColumnName
                                                     from: _alias];
}


#pragma mark - Internal


- (instancetype) initWithFrom: (nullable NSString*)alias {
    self = [super init];
    if (self) {
        _alias = alias;
    }
    return self;
}


@end
