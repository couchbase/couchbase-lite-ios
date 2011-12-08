//
//  ToyDB_Internal.h
//  ToyCouch
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "ToyDB.h"


@interface ToyDB (ViewInternals)

- (NSString*) versionOfView: (NSString*)viewName;
- (ToyDBStatus) setVersion: (NSString*)version ofView: (NSString*)viewName;
- (ToyDBStatus) deleteViewNamed: (NSString*)name;
- (BOOL) reindexView: (ToyView*)view;
- (NSArray*) dumpView: (NSString*)viewName;

@end
