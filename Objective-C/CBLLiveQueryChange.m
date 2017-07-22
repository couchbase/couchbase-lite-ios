//
//  CBLLiveQueryChange.m
//  CBL ObjC
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLLiveQueryChange+Internal.h"
#import "CBLLiveQuery.h"
#import "CBLQueryResultSet.h"

@implementation CBLLiveQueryChange

@synthesize query=_query, rows=_rows, error=_error;

- (instancetype) initWithQuery: (CBLLiveQuery*)query
                          rows: (CBLQueryResultSet*)rows
                         error: (NSError*)error {
    self = [super init];
    if (self) {
        _query = query;
        _rows = rows;
        _error = error;
    }
    return self;
}

@end
