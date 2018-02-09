//
//  CBLQueryChange.m
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
