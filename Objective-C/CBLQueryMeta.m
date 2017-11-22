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

@implementation CBLQueryMeta


+ (CBLQueryExpression*) id {
    return [self idFrom: nil];
}


+ (CBLQueryExpression*) idFrom: (NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaIDKeyPath
                                               columnName: kCBLQueryMetaIDColumnName
                                                     from: alias];
}


+ (CBLQueryExpression*) sequence {
    return [self sequenceFrom: nil];
}


+ (CBLQueryExpression*) sequenceFrom:(NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaSequenceKeyPath
                                               columnName: kCBLQueryMetaSequenceColumnName
                                                     from: alias];
}


@end
