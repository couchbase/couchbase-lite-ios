//
//  CBLQueryDataSource.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryDataSource.h"
#import "CBLDatabase.h"
#import "CBLQuery+Internal.h"

@implementation CBLQueryDataSource


@synthesize source=_source, alias=_alias;


- (instancetype) initWithDataSource:(id)source as:(nullable NSString*)alias {
    _source = source;
    _alias = alias;
    return [super init];
}


- (id) asJSON {
    return _alias ?  @{@"AS": _alias} : @{ };
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
    return [CBLQueryDataSource database: database as: nil];
}


+ (instancetype) database: (CBLDatabase*)database as: (nullable NSString*)alias {
    return [[CBLQueryDataSource alloc] initWithDataSource: database as: alias];
}


@end
