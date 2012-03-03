//
//  EmptyGNUstepApp.m
//  TouchDB
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TouchDB/TouchDB.h>
#import <TouchDB/TDRouter.h>

#if DEBUG
#import "Logging.h"
#import "Test.h"
#else
#define Warn NSLog
#define Log NSLog
#endif


int main (int argc, const char * argv[])
{
    @autoreleasepool {
#if DEBUG
        EnableLog(YES);
        //EnableLogTo(TDDatabase, YES);
        //EnableLogTo(TDDatabaseVerbose, YES);
        RunTestCases(argc, argv);
#endif
        /*
        NSError* error;
        TDServer* server = [[TDServer alloc] initWithDirectory: @"/tmp/touchdbserver" error: &error];
        if (!server) {
            Warn(@"FATAL: Error initializing TDServer: %@", error);
            exit(1);
        }
        NSLog(@"Started server %@", server);
        
        [[NSRunLoop currentRunLoop] run];
         */
        
    }
    return 0;
}

