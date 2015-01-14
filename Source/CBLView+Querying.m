//
//  CBLView+Querying.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

extern "C" {
#import "CBLView+Internal.h"
#import "CBLInternal.h"
#import "CouchbaseLitePrivate.h"
#import "CBLMisc.h"
#import "ExceptionUtils.h"
}


@implementation CBLView (Querying)


/** Main internal call to query a view. */
- (CBLQueryIteratorBlock) _queryWithOptions: (CBLQueryOptions*)options
                                     status: (CBLStatus*)outStatus
{
    if (!options)
        options = [CBLQueryOptions new];
    CBLQueryIteratorBlock iterator;
    if (options.fullTextQuery) {
        iterator = [_storage fullTextQueryWithOptions: options status: outStatus];
    } else if ([self groupOrReduceWithOptions: options])
        iterator = [_storage reducedQueryWithOptions: options status: outStatus];
    else
        iterator = [_storage regularQueryWithOptions: options status: outStatus];
    LogTo(Query, @"Query %@: Returning iterator", _name);
    return iterator;
}


// Should this query be run as grouped/reduced?
- (BOOL) groupOrReduceWithOptions: (CBLQueryOptions*) options {
    if (options->group || options->groupLevel > 0)
        return YES;
    else if (options->reduceSpecified)
        return options->reduce;
    else
        return (self.reduceBlock != nil); // Reduce defaults to true iff there's a reduce block
}


@end
