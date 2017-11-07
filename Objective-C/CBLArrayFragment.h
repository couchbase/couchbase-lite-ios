//
//  CBLArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLArrayFragment protocol provides subscript access to CBLFragment
 objects by index. 
 */
@protocol CBLArrayFragment <NSObject>

/** 
 Subscript access to a CBLFragment object by index.
 
 @param index The index.
 @return The CBLFragment object.
 */
- (nullable CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

NS_ASSUME_NONNULL_END

