//
//  CBLConflictResolver.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import "CBLConflictResolver.h"
#import "CBLDocument.h"
#import "CBLDocument+Internal.h"
#import "CBLDatabase+Internal.h"


@implementation CBLDefaultConflictResolver

- (nullable CBLDocument*) resolve: (CBLConflict*)conflict {
    // Default resolution algorithm:
    // 1. DELETE always wins.
    // 2. Most active wins (Higher generation number).
    // 3. Higher RevID wins.
    CBLDocument *mine = conflict.mine, *theirs = conflict.theirs;
    if (theirs.isDeleted)
        return theirs;
    else if (mine.isDeleted)
        return mine;
    else if (mine.generation > theirs.generation)
        return mine;
    else if (mine.generation < theirs.generation)
        return theirs;
    else if ([mine.revID compare: theirs.revID] > 0)
        return mine;
    else
        return theirs;
}

@end


@implementation CBLConflict

@synthesize mine=_mine, theirs=_theirs, base=_base;

- (instancetype) initWithMine: (CBLDocument*)mine
                       theirs: (CBLDocument*)theirs
                         base: (CBLDocument*)base
{
    self = [super init];
    if (self) {
        _mine = mine;
        _theirs = theirs;
        _base = base;
    }
    return self;
}

@end
