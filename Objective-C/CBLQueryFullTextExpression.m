//
//  CBLQueryFullTextExpression.m
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

#import "CBLQueryFullTextExpression.h"
#import "CBLQueryFullTextFunction.h"

@interface CBLQueryFullTextExpression ()

- (instancetype) initWithIndexName: (NSString*)name;

@end

// TODO: Remove https://issues.couchbase.com/browse/CBL-3206
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

@implementation CBLQueryFullTextExpression {
    NSString* _name;
}

- /* internal */ (instancetype) initWithIndexName: (NSString*)name {
    self = [super init];
    if (self) {
        _name = name;
    }
    return self;
}

+ (CBLQueryFullTextExpression*) indexWithName: (NSString*)name {
    CBLAssertNotNil(name);
    
    return [[self alloc] initWithIndexName: name];
}

- (CBLQueryExpression*) match: (NSString*)query {
    CBLAssertNotNil(query);
    
    return [CBLQueryFullTextFunction matchWithIndexName: _name
                                                  query: query];
}

@end
#pragma clang diagnostic pop
