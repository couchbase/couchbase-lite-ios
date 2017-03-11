//
//  CBLQueryDataSource.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryDataSource.h"
#import "CBLDatabase.h"
#import "CBLXQuery+Internal.h"

@implementation CBLQueryDataSource


@synthesize source=_source;


- (instancetype) initWithDataSource:(id)source {
    _source = source;
    return [super init];
}


+ (CBLQueryDatabase*) database: (CBLDatabase*)database {
    return [[CBLQueryDatabase alloc] initWithDatabase: database];
}


@end


@implementation CBLQueryDatabase


- (instancetype) initWithDatabase: (CBLDatabase*)database {
    return [super initWithDataSource: database];
}


@end
