//
//  OpenIDController+AppKit.h
//  Couchbase Lite
//
//  Created by Jens Alfke on 1/9/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OpenIDController.h"

NS_ASSUME_NONNULL_BEGIN

@interface OpenIDController (AppKit)

/** A view controller that hosts the login UI. */
@property (nonatomic,readonly) NSViewController* viewController;

/** A panel window containing the login view controller. */
@property (nonatomic,readonly) NSPanel* panel;

@end

NS_ASSUME_NONNULL_END
