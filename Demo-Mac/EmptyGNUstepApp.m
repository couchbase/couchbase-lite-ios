//
//  EmptyGNUstepApp.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CouchbaseLite/CouchbaseLite.h>
#import <CouchbaseLite/CBLRouter.h>

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
        //EnableLogTo(CBLDatabase, YES);
        //EnableLogTo(CBLDatabaseVerbose, YES);
        RunTestCases(argc, argv);
#endif
        /*
        NSError* error;
        CBLServer* server = [[CBLServer alloc] initWithDirectory: @"/tmp/touchdbserver" error: &error];
        if (!server) {
            Warn(@"FATAL: Error initializing CBLServer: %@", error);
            exit(1);
        }
        NSLog(@"Started server %@", server);
        
        [[NSRunLoop currentRunLoop] run];
         */
        
    }
    return 0;
}

