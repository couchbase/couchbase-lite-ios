//
//  CBLQueryResultsArray.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryResultsArray.h"
#import "CBLQueryEnumerator.h"
#import "CBLQuery+Internal.h"
#import "CBLQueryRow.h"
#import "CBLDatabase.h"
#import "CBLCoreBridge.h"


@implementation CBLQueryResultsArray
{
    id _enum;
    NSUInteger _count;
}

- (instancetype) initWithEnumerator: (id)enumerator
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
