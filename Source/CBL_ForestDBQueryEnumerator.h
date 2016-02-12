//
//  CBL_ForestDBQueryEnumerator.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/11/16.
//  Copyright © 2016 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#include "c4View.h"
@class CBL_ForestDBViewStorage, CBLQueryOptions;


@interface CBL_ForestDBQueryEnumerator : NSEnumerator

- (instancetype) initWithStorage: (CBL_ForestDBViewStorage*)viewStorage
                          C4View: (C4View*)c4view
                         options: (CBLQueryOptions*)options
                           error: (C4Error*)outError;

@end
