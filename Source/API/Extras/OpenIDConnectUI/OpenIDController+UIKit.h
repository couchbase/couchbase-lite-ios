//
//  OpenIDController+UIKit.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OpenIDController.h"

NS_ASSUME_NONNULL_BEGIN

@interface OpenIDController (UIKit)

/** A UIViewController that contains the OpenID login UI. */
@property (readonly) UIViewController* viewController;

/** A convenience method that puts the receiver in a UINavigationController and presents it modally
 in the given parent controller. */
- (UINavigationController*) presentModalInController: (UIViewController*)parentController;

@end

NS_ASSUME_NONNULL_END
