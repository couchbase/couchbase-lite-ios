//
//  CBLQueryRowsArray.m
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

#import "CBLQueryRowsArray.h"
#import "CBLQueryEnumerator.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryRow.h"
#import "CBLDatabase.h"
#import "CBLCoreBridge.h"


@implementation CBLQueryRowsArray
{
    CBLQueryEnumerator* _enum;
    NSUInteger _count;
}

- (instancetype) initWithEnumerator: (CBLQueryEnumerator*)enumerator
                              count: (NSUInteger)count
{
    self = [super init];
    if (self) {
        _enum = enumerator;
        _count = count;
    }
    return self;
}


- (NSUInteger) count {
    return _count;
}


- (id) objectAtIndex: (NSUInteger)index {
    return [_enum objectAtIndex: index];
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
