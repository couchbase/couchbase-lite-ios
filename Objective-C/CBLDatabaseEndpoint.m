//
//  CBLDatabaseEndpoint.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLDatabaseEndpoint.h"
#import "CBLDatabase.h"

@implementation CBLDatabaseEndpoint

@synthesize database=_database;

- (instancetype) initWithDatabase: (CBLDatabase*)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

@end
