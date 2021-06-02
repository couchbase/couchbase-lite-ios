//
//  main.m
//  CouchbaseLite
//
//  Created by Jayahari Vavachan on 6/1/21.
//  Copyright © 2021 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "c4.h"

__attribute__((constructor))
static void initialize()
{
    static int initialized = 0;
    if (!initialized)
    {
        initialized = 1;
        
        NSLog(@">>>>>>>>>>>>>>>>>>>>>>>>>>> main initializer!!");
        c4log_enableFatalExceptionBacktrace();
    }
}
