//
//  CBLConflictResolution.m
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLConflictResolution.h"
#import "CBLConflictResolver.h"
#import "CBLDocument+Internal.h"
#import "CBLConflict.h"

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
