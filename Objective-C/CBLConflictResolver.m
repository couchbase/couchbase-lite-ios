//
//  CBLConflictResolver.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLConflictResolver.h"
#import "CBLReadOnlyDocument.h"
#import "CBLDocument+Internal.h"
#import "CBLInternal.h"


@implementation CBLDefaultConflictResolver

- (nullable CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict {
    // Default resolution algorithm is "most active wins", i.e. higher generation number.
    CBLReadOnlyDocument *mine = conflict.mine, *theirs = conflict.theirs;
    if (mine.generation >= theirs.generation)       // hope I die before I get old
        return mine;
    else
        return theirs;
}

@end




@implementation CBLConflict


@synthesize mine=_mine, theirs=_theirs, base=_base;


- (instancetype) initWithMine: (CBLReadOnlyDocument*)mine
                       theirs: (CBLReadOnlyDocument*)theirs
                         base: (CBLReadOnlyDocument*)base
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
