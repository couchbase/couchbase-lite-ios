//
//  CBLMutableDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#import "CBLDictionaryFragment.h"
@class CBLMutableFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLMutableDictionaryFragment protocol provides subscript access to CBLMutableFragment objects by key. 
 */
@protocol CBLMutableDictionaryFragment <CBLDictionaryFragment>

/** 
 Subscript access to a CBLMutableFragment object by key.
 
 @param key The key.
 @return The CBLMutableFragment object.
 */
- (nullable CBLMutableFragment*) objectForKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
