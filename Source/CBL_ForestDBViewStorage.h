//
//  CBL_ForestDBViewStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_ViewStorage.h"
@class CBL_ForestDBStorage, MYAction;


@interface CBL_ForestDBViewStorage : NSObject <CBL_ViewStorage>

// internal:
- (instancetype) initWithDBStorage: (CBL_ForestDBStorage*)dbStorage
                              name: (NSString*)name
                            create: (BOOL)create;
+ (NSString*) fileNameToViewName: (NSString*)fileName;

- (MYAction*) actionToChangeEncryptionKey;

- (void) closeIndex;

@end
