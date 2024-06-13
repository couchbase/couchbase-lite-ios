//
//  CBLQueryIndex.mm
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLDatabase+Internal.h"
#import "CBLQueryIndex+Internal.h"
#import "CBLCoreBridge.h"
#import "CBLStatus.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLIndexUpdater+Internal.h"
#endif

@implementation CBLQueryIndex {
    // retained database mutex
    id _mutex;
}

@synthesize collection = _collection, name = _name, c4index = _c4index;

- (instancetype) initWithC4Index: (C4Index*) c4index
                            name: (NSString*) name
                      collection: (CBLCollection*) collection {
    self = [super init];
    if (self) {
        _c4index = c4index;
        _collection = collection;
        // grab name from c4index
        _name = name;
        _mutex = _collection.database.mutex;
    }
    return self;
}

- (void) dealloc {
    c4index_release(_c4index);
}

#ifdef COUCHBASE_ENTERPRISE

- (nullable CBLIndexUpdater*) beginUpdate:(uint64_t) limit 
                                    error:(NSError*) error {
    CBL_LOCK(_mutex){
        C4Error c4err = {};
        C4IndexUpdater* _c4updater = c4index_beginUpdate(_c4index, (size_t)limit, &c4err);
        
        if(!_c4updater) {
            if(c4err.code != 0) {
                convertError(c4err, &error);
            }
            return nil;
        }
        
        return [[CBLIndexUpdater alloc] initWithC4Updater:_c4updater
                                               queryIndex: self];
    }
}

#endif

- (id) mutex {
    return _mutex;
}

@end
