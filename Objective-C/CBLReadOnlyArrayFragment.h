//
//  CBLReadOnlyArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLReadOnlyFragment;

/** CBLReadOnlyArrayFragment protocol provides subscript access to CBLReadOnlyFragment 
    objects by index. */
@protocol CBLReadOnlyArrayFragment <NSObject>

/** Gets a CBLReadOnlyFragment object by index.
    @param index  the index.
    @result the CBLReadOnlyFragment object. */
- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end
