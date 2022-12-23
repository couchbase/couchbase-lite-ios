//
//  CBLQueryFullTextIndexExpression.m
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

#import "CBLQueryFullTextIndexExpression.h"
#import "CBLQueryFullTextIndexExpressionProtocol.h"

@implementation CBLQueryFullTextIndexExpression {
    NSString* _alias;
    NSString* _name;
}

- (instancetype) init: (NSString*)indexName {
    self = [super init];
    if (self) {
        _name = indexName;
    }
    return self;
}

- (id<CBLQueryIndexExpressionProtocol>) from: (NSString*)alias {
    _alias = alias;
    return self;
}

- (NSString*) stringValue {
    return _alias.length > 0 ? $sprintf(@"%@.%@", _alias, _name) : _name;
}

@end
