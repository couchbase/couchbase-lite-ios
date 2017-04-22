//
//  CBLReadOnlyArrayFragment.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

@class CBLReadOnlyFragment;

@protocol CBLReadOnlyArrayFragment <NSObject>

- (CBLReadOnlyFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end
