//
//  CBLKVOProxy.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"

@interface CBLKVOProxy : NSObject

- (CBLKVOProxy*) initWithObject: (id)object
                        keyPath: (NSString*)keyPath;

@end
