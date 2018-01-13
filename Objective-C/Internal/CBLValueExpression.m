//
//  CBLValueExpression.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/12/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLValueExpression.h"
#import "CBLJSON.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLValueExpression {
    id _value;
}


- (instancetype) initWithValue: (nullable id)value {
    self = [super initWithNone];
    if (self) {
        [self validate: value];
        _value = value;
    }
    return self;
}


- (void) validate: (nullable id)value {
    if (!value ||
        [value isKindOfClass: [NSString class]] ||
        [value isKindOfClass: [NSNumber class]] ||
        [value isKindOfClass: [NSDate class]] ||
        value == [NSNull null]) {
        return;
    }
    
    [NSException raise: NSInternalInconsistencyException
                format: @"Unsupported value type: %@", value];
}


- (id) asJSON {
    if (!_value)
        return [NSNull null];
    
    if ([_value isKindOfClass: [NSDate class]])
        return [CBLJSON JSONObjectWithDate:_value];
    else
        return _value;
}


@end
