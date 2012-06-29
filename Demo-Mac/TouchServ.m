//
//  TouchServ.m
//  TouchServ
//
//  Created by Jens Alfke on 1/16/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <TouchDB/TouchDB.h>
#import <TouchDB/TDRouter.h>
#import <TouchDBListener/TDListener.h>

#if DEBUG
#import "Logging.h"
#else
#define Warn NSLog
#define Log NSLog
#endif


#define kPortNumber 59840


static NSString* GetServerPath() {
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID)
        bundleID = @"com.couchbase.TouchServ";
    
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString* path = [paths objectAtIndex:0];
    path = [path stringByAppendingPathComponent: bundleID];
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
#if DEBUG
        EnableLog(YES);
        EnableLogTo(TDListener, YES);
#endif
        
        NSError* error;
        TDServer* server = [[TDServer alloc] initWithDirectory: GetServerPath() error: &error];
        if (error) {
            Warn(@"FATAL: Error initializing TouchDB: %@", error);
            exit(1);
        }
        
        // Start a listener socket:
        TDListener* listener = [[TDListener alloc] initWithTDServer: server port: kPortNumber];
        
        // Advertise via Bonjour, and set a TXT record just as an example:
        [listener setBonjourName: @"TouchServ" type: @"_touchdb._tcp."];
        NSData* value = [@"value" dataUsingEncoding: NSUTF8StringEncoding];
        listener.TXTRecordDictionary = [NSDictionary dictionaryWithObject: value forKey: @"Key"];
        
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--readonly") == 0) {
                listener.readOnly = YES;
            } else if (strcmp(argv[i], "--auth") == 0) {
                srandomdev();
                NSString* password = [NSString stringWithFormat: @"%x", random()];
                listener.passwords = [NSDictionary dictionaryWithObject: password
                                                                 forKey: @"touchdb"];
                Log(@"Auth required: user='touchdb', password='%@'", password);
            }
        }
        
        [listener start];
        
        Log(@"TouchServ %@ is listening%@ on port %d ... relax!",
            [TDRouter versionString],
            (listener.readOnly ? @" in read-only mode" : @""),
            listener.port);
        
        [[NSRunLoop currentRunLoop] run];
        
        [listener release];
        [server release];
    }
    return 0;
}

