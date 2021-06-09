//
//  CBLIndexConfiguration.m
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

#import "CBLIndexConfiguration.h"
#import "CBLBaseIndex+Internal.h"

@implementation CBLIndexConfiguration {
    NSString* _expressions;
}

- (instancetype) initWithIndexType: (C4IndexType)type expression: (NSString*)expression {
    self = [super initWithIndexType: type queryLanguage: kC4N1QLQuery];
    if (self) {
        _expressions = expression;
    }
    return self;
}

- (NSString*) getIndexSpecs {
    return _expressions;
}

@end

@implementation CBLFullTextIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression {
    return [super initWithIndexType: kC4FullTextIndex expression: expression];
}

@end

@implementation CBLValueIndexConfiguration

- (instancetype) initWithExpression: (NSString*)expression {
    return [super initWithIndexType: kC4ValueIndex expression: expression];
}

@end

