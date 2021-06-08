//
//  CBLBaseIndex.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/7/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import "CBLBaseIndex.h"

@implementation CBLBaseIndex

@synthesize indexType=_indexType, queryLanguage=_queryLanguage;

- (instancetype) initWithIndexType: (C4IndexType)indexType
                     queryLanguage: (C4QueryLanguage)language {
    self = [super init];
    if (self) {
        _indexType = indexType;
        _queryLanguage = language;
    }
    return self;
}

- (NSString*) getIndexSpecs {
    // Implement by subclass
    [NSException raise: NSInternalInconsistencyException
                format: @"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
    return nil;
}

- (C4IndexOptions) indexOptions {
    // default empty options
    return (C4IndexOptions){ };
}

@end

