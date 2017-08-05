//
//  CBLDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#import "CBLReadOnlyDictionaryFragment.h"
@class CBLFragment;

/** 
 CBLDictionaryFragment protocol provides subscript access to CBLFragment objects by key. 
 */
@protocol CBLDictionaryFragment <CBLReadOnlyDictionaryFragment>

/** 
 Subscript access to a CBLFragment object by key.
 
 @param key The key.
 @return The CBLFragment object.
 */
- (CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

