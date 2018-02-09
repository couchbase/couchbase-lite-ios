//
//  ExampleConflictResolver.m
//  objc-api-walkthrough
//
//  Created by James Nocentini on 27/07/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

#import "ExampleConflictResolver.h"

@implementation ExampleConflictResolver

- (nullable CBLDocument*) resolve: (CBLConflict*)conflict {
    CBLDocument* base = conflict.base;
    CBLDocument* mine = conflict.mine;
    CBLDocument* theirs = conflict.theirs;
    return theirs;
}

@end
