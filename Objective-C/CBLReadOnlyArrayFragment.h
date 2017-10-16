//
//  CBLReadOnlyArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLReadOnlyFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLReadOnlyArrayFragment protocol provides subscript access to CBLReadOnlyFragment
 objects by index. 
 */
@protocol CBLReadOnlyArrayFragment <NSObject>

/** 
 Subscript access to a CBLReadOnlyFragment object by index.
 
 @param index The index.
 @return The CBLReadOnlyFragment object.
 */
- (nullable CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

NS_ASSUME_NONNULL_END

