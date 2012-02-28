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
#else
#define Warn NSLog
#define Log NSLog
#endif


int main (int argc, const char * argv[])
{
    @autoreleasepool {
#if DEBUG
        EnableLog(YES);
        EnableLogTo(TDListener, YES);
#endif
        
        NSError* error;
        TDServer* server = [[TDServer alloc] initWithDirectory: @"/tmp/touchdbserver" error: &error];
        if (error) {
            Warn(@"FATAL: Error initializing TouchDB: %@", error);
            exit(1);
        }
        NSLog(@"Started server %@", server);
        
        [[NSRunLoop currentRunLoop] run];
        
    }
    return 0;
}

