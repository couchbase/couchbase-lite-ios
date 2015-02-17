//
//  CBL_SQLiteViewStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/16/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_ViewStorage.h"
@class CBL_SQLiteStorage;


@interface CBL_SQLiteViewStorage : NSObject <CBL_ViewStorage, CBL_QueryRowStorage>

- (instancetype) initWithDBStorage: (CBL_SQLiteStorage*)dbStorage
                              name: (NSString*)name
                            create: (BOOL)create;

@end
