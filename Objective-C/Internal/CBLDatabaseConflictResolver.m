//
//  CBLDatabaseConflictResolver.m
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/24.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLDatabaseConflictResolver.h"

@implementation CBLDatabaseConflictResolver

- (NSDictionary *)resolveSource:(NSDictionary *)source withTarget:(NSDictionary *)target andBase:(NSDictionary *)base {
    return target;
}

@end
