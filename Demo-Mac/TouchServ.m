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
#import <TouchDB/TDReplicator.h>
#import <TouchDB/TDDatabaseManager.h>
#import <TouchDB/TDDatabase+Replication.h>

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


static bool doReplicate( TDServer* server, const char* replArg, BOOL pull) {
    NSURL* remote = [NSMakeCollectable(CFURLCreateWithBytes(NULL, (const UInt8*)replArg,
                                                           strlen(replArg),
                                                           kCFStringEncodingUTF8, NULL)) autorelease];
    if (!remote || !remote.scheme) {
        fprintf(stderr, "Invalid remote URL <%s>\n", replArg);
        return false;
    }
    NSString* dbName = remote.lastPathComponent;
    if (dbName.length == 0) {
        fprintf(stderr, "Invalid database name '%s'\n", dbName.UTF8String);
        return false;
    }
    
    if (pull)
        Log(@"Pulling from <%@> --> %@ ...", remote, dbName);
    else
        Log(@"Pushing %@ --> <%@> ...", dbName, remote);
    
    [server tellDatabaseManager: ^(TDDatabaseManager *dbm) {
        TDReplicator* repl = nil;
        TDDatabase* db = [dbm existingDatabaseNamed: dbName];
        if (pull) {
            if (db) {
                if (![db deleteDatabase: nil]) {
                    fprintf(stderr, "Couldn't delete existing database '%s'\n", dbName.UTF8String);
                    return;
                }
                db = [dbm databaseNamed: dbName];
            }
        }
        if (!db) {
            fprintf(stderr, "No such database '%s'\n", dbName.UTF8String);
            return;
        }
        [db open];
        repl = [db replicatorWithRemoteURL: remote push: !pull continuous: NO];
        if (!repl)
            fprintf(stderr, "Unable to create replication.\n");
        [repl start];
    }];
        
    return true;
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
        [TDURLProtocol setServer: server];
        
        // Start a listener socket:
        TDListener* listener = [[TDListener alloc] initWithTDServer: server port: kPortNumber];
        
        // Advertise via Bonjour, and set a TXT record just as an example:
        [listener setBonjourName: @"TouchServ" type: @"_touchdb._tcp."];
        NSData* value = [@"value" dataUsingEncoding: NSUTF8StringEncoding];
        listener.TXTRecordDictionary = [NSDictionary dictionaryWithObject: value forKey: @"Key"];
        
        const char* replArg = NULL;
        BOOL pull = NO;
        
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--readonly") == 0) {
                listener.readOnly = YES;
            } else if (strcmp(argv[i], "--auth") == 0) {
                srandomdev();
                NSString* password = [NSString stringWithFormat: @"%lx", random()];
                listener.passwords = [NSDictionary dictionaryWithObject: password
                                                                 forKey: @"touchdb"];
                Log(@"Auth required: user='touchdb', password='%@'", password);
            } else if  (strcmp(argv[i], "--pull") == 0) {
                replArg = argv[i+1];
                pull = YES;
            } else if  (strcmp(argv[i], "--push") == 0) {
                replArg = argv[i+1];
            }
        }
        
        [listener start];
        
        if (replArg) {
            if (!doReplicate(server, replArg, pull))
                return 1;
        } else {
            Log(@"TouchServ %@ is listening%@ on port %d ... relax!",
                [TDRouter versionString],
                (listener.readOnly ? @" in read-only mode" : @""),
                listener.port);
        }
        
        [[NSRunLoop currentRunLoop] run];
        
        Log(@"TouchServ quitting");
        [listener release];
        [server release];
    }
    return 0;
}

