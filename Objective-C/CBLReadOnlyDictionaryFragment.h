//
//  ReadOnlyDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLReadOnlyFragment;

/** CBLReadOnlyDictionaryFragment protocol provides subscript access to CBLReadOnlyFragment
    objects by key. */
@protocol CBLReadOnlyDictionaryFragment <NSObject>

/** Subscript access to a CBLReadOnlyFragment object by key.
    @param key  the key.
    @result the CBLReadOnlyFragment object. */
- (CBLReadOnlyFragment*) objectForKeyedSubscript: (NSString*)key;

@end
