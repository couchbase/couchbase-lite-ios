//
//  CBLLiveQueryChange.m
//  CBL ObjC
//
//  Created by Pasin Suriyentrakorn on 6/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLQueryChange+Internal.h"
#import "CBLQuery.h"
#import "CBLQueryResultSet.h"

@implementation CBLQueryChange

@synthesize query=_query, results=_results, error=_error;

- (instancetype) initWithQuery: (CBLQuery*)query
                       results: (CBLQueryResultSet*)results
                         error: (NSError*)error {
    self = [super init];
    if (self) {
        _query = query;
        _results = results;
        _error = error;
    }
    return self;
}

@end
