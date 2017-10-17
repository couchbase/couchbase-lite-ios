//
//  ReadOnlyDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLReadOnlyFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLReadOnlyDictionaryFragment protocol provides subscript access to CBLReadOnlyFragment
 objects by key.
 */
@protocol CBLReadOnlyDictionaryFragment <NSObject>

/** 
 Subscript access to a CBLReadOnlyFragment object by key.
 
 @param key The key.
 @return The CBLReadOnlyFragment object.
 */
- (nullable CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
