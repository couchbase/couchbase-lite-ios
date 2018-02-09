//
//  CBLValueExpression.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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
