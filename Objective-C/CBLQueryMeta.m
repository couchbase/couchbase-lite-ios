//
//  CBLQueryMeta.m
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


+ (CBLQueryExpression*) idFrom: (nullable NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaIDKeyPath
                                               columnName: kCBLQueryMetaIDColumnName
                                                     from: alias];
}


+ (CBLQueryExpression*) sequence {
    return [self sequenceFrom: nil];
}


+ (CBLQueryExpression*) sequenceFrom:(nullable NSString *)alias {
    return [[CBLPropertyExpression alloc] initWithKeyPath: kCBLQueryMetaSequenceKeyPath
                                               columnName: kCBLQueryMetaSequenceColumnName
                                                     from: alias];
}


@end
