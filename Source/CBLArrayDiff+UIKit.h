//
//  CBLArrayDiff+UIKit.h
//  Mutant
//
//  Created by Jens Alfke on 3/10/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import "CBLArrayDiff.h"
#import <UIKit/UITableView.h>

@interface CBLArrayDiff (UIKit)

- (void) animateTableView: (UITableView*)tableView
        deletionAnimation: (UITableViewRowAnimation)deletionAnimation
         replaceAnimation: (UITableViewRowAnimation)replaceAnimation
       insertionAnimation: (UITableViewRowAnimation)insertionAnimation;

@end
