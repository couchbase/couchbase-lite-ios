//
//  CBLArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLReadOnlyArrayFragment.h"
@class CBLFragment;

@protocol CBLArrayFragment <CBLReadOnlyArrayFragment>

- (CBLFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end
