//
//  CBL_ForestDBDocEnumerator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/12/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

extern "C" {
    #import "CBLQuery.h"
    #import "CBLView+Internal.h"
}
#include "c4View.h"
@class CBL_ForestDBStorage;


@interface CBL_ForestDBDocEnumerator : CBLQueryEnumerator

- (instancetype) initWithStorage: (CBL_ForestDBStorage*)storage
                         options: (CBLQueryOptions*)options
                           error: (C4Error*)outError;

@end
