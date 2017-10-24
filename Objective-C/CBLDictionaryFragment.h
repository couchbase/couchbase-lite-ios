//
//  ReadOnlyDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLDictionaryFragment protocol provides subscript access to CBLFragment
 objects by key.
 */
@protocol CBLDictionaryFragment <NSObject>

/** 
 Subscript access to a CBLFragment object by key.
 
 @param key The key.
 @return The CBLFragment object.
 */
- (nullable CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
