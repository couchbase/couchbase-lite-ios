//
//  CBLConflictResolution.m
//  CBL ObjC
//
//  Created by Jayahari Vavachan on 4/26/19.
//  Copyright © 2019 Couchbase. All rights reserved.
//

#import "CBLConflictResolution.h"
#import "CBLConflictResolver.h"
#import "CBLDocument+Internal.h"

@interface CBLDefaultConflictResolution : NSObject <CBLConflictResolver>

@end

@implementation CBLConflictResolution

+ (id) default {
    return [[CBLDefaultConflictResolution alloc] init];
}

@end

@implementation CBLDefaultConflictResolution

- (nullable CBLDocument*) resolve: (CBLConflict*)conflict {
    if (conflict.remoteDocument == nil || conflict.localDocument == nil)
        return nil;
    else if (conflict.localDocument.generation > conflict.remoteDocument.generation)
        return conflict.localDocument;
    else if (conflict.localDocument.generation < conflict.remoteDocument.generation)
        return conflict.remoteDocument;
    else if ([conflict.localDocument.revID compare: conflict.remoteDocument.revID] > 0)
        return conflict.localDocument;
    else
        return conflict.remoteDocument;
}

@end
