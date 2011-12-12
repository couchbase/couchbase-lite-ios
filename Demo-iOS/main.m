//
//  main.m
//  iOS Demo
//
//  Created by Jens Alfke on 12/9/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Test.h"

#import "DemoAppDelegate.h"

int main(int argc, char *argv[])
{
    @autoreleasepool {
        RunTestCases(argc,(const char**)argv);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([DemoAppDelegate class]));
    }
}
