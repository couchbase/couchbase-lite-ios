//
//  CBLQueryResultArray.m
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

#import "CBLQueryResultArray.h"
#import "CBLQueryResultSet+Internal.h"

@implementation CBLQueryResultArray
{
    CBLQueryResultSet* _rs;
    NSUInteger _count;
}

- (instancetype) initWithResultSet: (CBLQueryResultSet*)resultSet count: (NSUInteger)count {
    self = [super init];
    if (self) {
        _rs = resultSet;
        _count = count;
    }
    return self;
}


- (NSUInteger) count {
    return _count;
}


- (id) objectAtIndex: (NSUInteger)index {
    return [_rs objectAtIndex: index];
}


- (id) copyWithZone:(NSZone *)zone {
    return self;
}


- (NSMutableArray*) mutableCopy {
    NSMutableArray* m = [[NSMutableArray alloc] initWithCapacity: _count];
    for (NSUInteger i = 0; i < _count; ++i)
        [m addObject: [self objectAtIndex: i]];
    return m;
}


// This is what the %@ substitution calls.
- (NSString *)descriptionWithLocale:(id)locale indent:(NSUInteger)level {
    return [NSString stringWithFormat: @"%@[%lu rows]", [self class], (unsigned long)_count];
}


@end
