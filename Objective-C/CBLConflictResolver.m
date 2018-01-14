//
//  CBLConflictResolver.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
