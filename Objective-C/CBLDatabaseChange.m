//
//  CBLDatabaseChange.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseChange.h"
#import "CBLDatabase+Internal.h"

@implementation CBLDatabaseChange

@synthesize database=_database, documentIDs=_documentIDs, isExternal=_isExternal;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                      documentIDs: (NSArray *)documentIDs
                       isExternal: (BOOL)isExternal
{
    self = [super init];
    if (self) {
        _database = database;
        _documentIDs = documentIDs;
        _isExternal = isExternal;
    }
    return self;
}

@end
