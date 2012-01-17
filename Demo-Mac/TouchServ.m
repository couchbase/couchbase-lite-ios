//
//  main.m
//  TouchServ
//
//  Created by Jens Alfke on 1/16/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TouchDB/TouchDB.h>
#import <TouchDBListener/TDListener.h>


#define kPortNumber 59840


static NSString* GetServerPath() {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString* path = [paths objectAtIndex:0];
    path = [path stringByAppendingPathComponent: [[NSBundle mainBundle] bundleIdentifier]];
    path = [path stringByAppendingPathComponent: @"TouchDB"];
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath: path
                                  withIntermediateDirectories: YES
                                                   attributes: nil error: &error]) {
        NSLog(@"FATAL: Couldn't create TouchDB server dir at %@", path);
        exit(1);
    }
    return path;
}


int main (int argc, const char * argv[])
{
    @autoreleasepool {
        NSError* error;
        TDServer* server = [[TDServer alloc] initWithDirectory: GetServerPath() error: &error];
        if (error) {
            NSLog(@"FATAL: Error initializing TouchDB: %@", error);
            exit(1);
        }
        
        // Start a listener socket:
        TDListener* listener = [[TDListener alloc] initWithTDServer: server port: kPortNumber];
        [listener start];
        
        NSLog(@"TouchServ is listening on port %d ... relax!", kPortNumber);
        
        [[NSRunLoop currentRunLoop] run];
        
    }
    return 0;
}

