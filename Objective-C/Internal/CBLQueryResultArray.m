//
//  CBLQueryResultArray.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
