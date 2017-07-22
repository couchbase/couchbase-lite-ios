//
//  CBLFLArray.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFLArray.h"
#import "CBLC4Document.h"
#import "CBLDatabase.h"

@implementation CBLFLArray

@synthesize array=_array, datasource=_datasource, database=_database;

- (instancetype) initWithArray: (nullable FLArray) array
                    datasource: (id<CBLFLDataSource>)datasource
                      database: (CBLDatabase*)database
{
    self = [super init];
    if (self) {
        _array = array;
        _datasource = datasource;
        _database = database;
    }
    return self;
}

@end
