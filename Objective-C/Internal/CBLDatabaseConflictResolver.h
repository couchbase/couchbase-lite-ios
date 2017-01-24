//
//  CBLDatabaseConflictResolver.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/24.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"

// TODO: Decide on an appropriate algorithm here

/* The default conflict resolver for a database if none is specified */
@interface CBLDatabaseConflictResolver : NSObject <CBLConflictResolver>

- (NSDictionary *)resolveSource:(NSDictionary *)source withTarget:(NSDictionary *)target andBase:(NSDictionary *)base;

@end
