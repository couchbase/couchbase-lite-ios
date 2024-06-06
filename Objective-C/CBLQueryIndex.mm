//
//  CBLQueryIndex.m
//  CouchbaseLite
//
//  Created by Vlad Velicu on 28/05/2024.
//  Copyright © 2024 Couchbase. All rights reserved.
//

#import "CouchbaseLite/CBLDatabase+Internal.h"
#import "CouchbaseLite/CBLQueryIndex+Internal.h"
#import "CouchbaseLite/CBLIndexUpdater+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStatus.h"

@implementation CBLQueryIndex {
    // retained database mutex
    id _mutex;
}

@synthesize collection = _collection, name = _name, c4index=_c4index;

- (instancetype) initWithIndex: (C4Index*) index
                          name: (NSString*) name
                    collection: (CBLCollection*) collection {
    self = [super init];
    if (self) {
        _c4index = index;
        _collection = collection;
        _name = name;
        _mutex = _collection.database.mutex;
    }
    return self;
}

/**
  ENTERPRISE ONLY
 */

#ifdef COUCHBASE_ENTERPRISE

- (nullable CBLIndexUpdater*) beginUpdate:(uint64_t) limit error:(NSError**) error {
    // need to check for lazy
    
    CBL_LOCK(_mutex){
        C4Error c4err;
        C4IndexUpdater* _c4updater = c4index_beginUpdate(_c4index, (size_t)limit, &c4err);
        
        if(c4err) {
            convertError(c4err, error);
        }

        if (_c4updater) {
            CBLIndexUpdater* updater = [[CBLIndexUpdater alloc] initWithUpdater:_c4updater];
            updater.queryIndex = self;
            return updater;
        } else {
            return nil;
        }
    }
}

#endif

- (id) mutex {
    return _mutex;
}



@end
