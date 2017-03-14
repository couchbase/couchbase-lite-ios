//
//  CBLReplication+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/13/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "CBLReplication.h"
@class CBLDatabase;

@interface CBLReplication ()

- (instancetype) initWithDatabase: (CBLDatabase*)db
                              URL: (NSURL*)remote;

@end
