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
#import "CBLBlob.h"
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
        [value isKindOfClass: [NSDictionary class]] ||
        [value isKindOfClass: [NSArray class]] ||
        [value isKindOfClass: [CBLQueryExpression class]] ||
        value == [NSNull null]) {
        return;
    }
    
    [NSException raise: NSInternalInconsistencyException
                format: @"Unsupported value type: %@", value];
}


static id valueAsJSON(id value) {
    if (!value)
        return [NSNull null];
    if ([value isKindOfClass: [NSDate class]])
        return [CBLJSON JSONObjectWithDate: value];
    else if ([value isKindOfClass: [NSDictionary class]])
        return dictionaryAsJSON(value);
    else if ([value isKindOfClass: [NSArray class]])
        return arrayAsJSON(value);
    else if ([value isKindOfClass: [CBLQueryExpression class]])
        return [((CBLQueryExpression*)value) asJSON];
    else
        return value;
}


static id dictionaryAsJSON(NSDictionary* dict) {
    NSMutableDictionary *json =
        [NSMutableDictionary dictionaryWithCapacity: dict.count];
    for (NSString *key in dict) {
        json[key] = valueAsJSON(dict[key]);
    }
    return json;
}


static id arrayAsJSON(NSArray* array) {
    NSMutableArray *json = [NSMutableArray arrayWithCapacity: array.count];
    for (id value in array) {
        [json addObject: valueAsJSON(value)];
    }
    return json;
}


- (id) asJSON {
    return valueAsJSON(_value);
}


@end
