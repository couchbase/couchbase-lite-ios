//
//  CBLScope.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 5/17/22.
//  Copyright © 2022 Couchbase. All rights reserved.
//

#import "CBLScope.h"

@implementation CBLScope

@synthesize name;

- (CBLCollection*) getCollectionWithName: (NSString*)name {
    return [[CBLCollection alloc] init];
}

- (NSArray<CBLCollection*>*) getCollections {
    return [NSArray array];
}

@end
