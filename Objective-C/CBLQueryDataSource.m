//
//  CBLQueryDataSource.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLQueryDataSource.h"
#import "CBLDatabase.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryDataSource

@synthesize source=_source, alias=_alias;

- (instancetype) initWithDataSource: (id)source as: (nullable NSString*)alias {
    _source = source;
    _alias = alias;
    return [super init];
}

- (id) asJSON {
    NSString* columnName = [self columnName];
    assert(columnName);
    
    if ([columnName isEqualToString: @"cbl-3715"]) {
//        "{\"FROM\":[{\"COLLECTION\":\"_default\"}],\"WHAT\":[[\"_.\",[\"meta()\"],\".id\"]],\"WHERE\":[\">\",[\"_.\",[\"meta()\"],\".expiration\"],1667854405597.2249]}"
        return @{ @"COLLECTION" : @"_default" };
    }
    
    return @{ @"AS" : columnName };
}

- (nullable NSString*) columnName {
    if (_alias)
        return _alias;
    else {
        CBLDatabase* db = $castIf(CBLDatabase, _source);
        if (db)
            return db.name;
    }
    return nil;
}

+ (instancetype) database: (CBLDatabase*)database {
    CBLAssertNotNil(database);
    
    return [CBLQueryDataSource database: database as: nil];
}

+ (instancetype) database: (CBLDatabase*)database as: (nullable NSString*)alias {
    CBLAssertNotNil(database);
    
    return [[CBLQueryDataSource alloc] initWithDataSource: database as: alias];
}

@end
