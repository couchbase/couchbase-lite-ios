//
//  CBLDictionaryFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//


#import "CBLReadOnlyDictionaryFragment.h"
@class CBLFragment;

@protocol CBLDictionaryFragment <CBLReadOnlyDictionaryFragment>

- (CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

