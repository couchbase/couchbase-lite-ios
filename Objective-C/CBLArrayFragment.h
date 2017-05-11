//
//  CBLArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyArrayFragment.h"
@class CBLFragment;

/** CBLArrayFragment protocol provides subscript access to CBLFragment objects by index. */
@protocol CBLArrayFragment <CBLReadOnlyArrayFragment>

/** Gets a CBLFragment object by index.
    @param index  the index.
    @result the CBLFragment object. */
- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end
