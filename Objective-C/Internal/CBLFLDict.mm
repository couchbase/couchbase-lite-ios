//
//  CBLFLDict.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/23/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLFLDict.h"
#import "CBLC4Document.h"
#import "CBLDatabase.h"
#import "CBLSharedKeys.hh"

@implementation CBLFLDict

@synthesize dict=_dict, datasource=_datasource, database=_database;

- (instancetype) initWithDict: (nullable FLDict) dict
                   datasource: (id<CBLFLDataSource>)datasource
                     database: (CBLDatabase*)database {
    self = [super init];
    if (self) {
        _dict = dict;
        _datasource = datasource;
        _database = database;
    }
    return self;
}

@end
