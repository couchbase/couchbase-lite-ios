//
//  ExampleConflictResolver.m
//  objc-api-walkthrough
//
//  Created by James Nocentini on 27/07/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

#import "ExampleConflictResolver.h"

@implementation ExampleConflictResolver

- (nullable CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict {
    CBLReadOnlyDocument* base = conflict.base;
    CBLReadOnlyDocument* mine = conflict.mine;
    CBLReadOnlyDocument* theirs = conflict.theirs;
    
    return theirs;
}

@end
