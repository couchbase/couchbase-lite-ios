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

@implementation CBLFLDict {
    FLDict _dict;
    CBLC4Document* _c4doc;
    CBLDatabase* _database;
}

@synthesize dict=_dict, c4doc=_c4doc, database=_database;

- (instancetype) initWithDict: (nullable FLDict) dict
                        c4doc: (CBLC4Document*)c4doc
                     database: (CBLDatabase*)database {
    self = [super init];
    if (self) {
        _dict = dict;
        _c4doc = c4doc;
        _database = database;
    }
    return self;
}

@end
