//
//  CBLQueryLimit.m
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

#import "CBLQueryLimit.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryExpression+Internal.h"

@implementation CBLQueryLimit

@synthesize limit=_limit, offset=_offset;


+ (CBLQueryLimit*) limit: (CBLQueryExpression*)limit {
    return [self limit: limit offset: nil];
}


+ (CBLQueryLimit*) limit: (CBLQueryExpression*)limit
                  offset: (nullable CBLQueryExpression*)offset
{
    CBLAssertNotNil(limit);
    
    return [[self alloc] initWithLimit: limit offset: offset];
}


#pragma mark - Internal


- (instancetype) initWithLimit: (CBLQueryExpression*)limit
                        offset: (nullable CBLQueryExpression*)offset
{
    self = [super init];
    if (self) {
        _limit = limit;
        _offset = offset;
    }
    return self;
}


- (id) asJSON {
    NSMutableArray* json = [NSMutableArray array];
    
    if ([_limit isKindOfClass: [CBLQueryExpression class]])
        [json addObject: [(CBLQueryExpression*)_limit asJSON]];
    else
        [json addObject: _limit];
    
    if (_offset) {
        if ([_offset isKindOfClass: [CBLQueryExpression class]])
            [json addObject: [(CBLQueryExpression*)_offset asJSON]];
        else
            [json addObject: _offset];
    }
    
    return json;
}

@end
