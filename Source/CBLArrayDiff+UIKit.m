//
//  CBLArrayDiff+UIKit.m
//  Mutant
//
//  Created by Jens Alfke on 3/10/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import "CBLArrayDiff+UIKit.h"


@implementation CBLArrayDiff (UIKit)


- (void) animateTableView: (UITableView*)table
        deletionAnimation: (UITableViewRowAnimation)deletionAnimation
         replaceAnimation: (UITableViewRowAnimation)replaceAnimation
       insertionAnimation: (UITableViewRowAnimation)insertionAnimation
{
    [table beginUpdates];

    NSArray* deletions  = [CBLArrayDiff indexPathsForSet: self.deletedIndexes withSection: 0];
    [table deleteRowsAtIndexPaths: deletions
                  withRowAnimation: deletionAnimation];

    NSArray* insertions = [CBLArrayDiff indexPathsForSet: self.insertedIndexes withSection: 0];
    [table insertRowsAtIndexPaths: insertions
                  withRowAnimation: insertionAnimation];

    NSUInteger moveCount = self.moveCount;

    if (moveCount > 0) {
        [self forEachMove:^(NSUInteger before, NSUInteger after) {
            @autoreleasepool {
                [table moveRowAtIndexPath: [NSIndexPath indexPathForRow: before inSection: 0]
                               toIndexPath: [NSIndexPath indexPathForRow: after  inSection: 0]];
            }
        }];
        // If there are moves, end the animation before doing the reloads, because the two types
        // of animations don't combine properly.
        [table endUpdates];
    }

    NSIndexSet* changes = (moveCount==0 ? self.changedIndexesBefore : self.changedIndexesAfter);
    NSArray* reloads = [CBLArrayDiff indexPathsForSet: changes withSection: 0];
    [table reloadRowsAtIndexPaths: reloads
                  withRowAnimation: replaceAnimation];

    if (moveCount == 0) {
        [table endUpdates];
    }
}


@end
