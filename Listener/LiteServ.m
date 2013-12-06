//
//  LiteServ.m
//  LiteServ
//
//  Created by Jens Alfke on 1/16/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import <Foundation/Foundation.h>
#import "CouchbaseLite.h"
#import "CouchbaseLitePrivate.h"
#import "CBL_Router.h"
#import "CBLListener.h"
#import "CBL_Pusher.h"
#import "CBLManager+Internal.h"
#import "CBLDatabase+Replication.h"
#import "CBLMisc.h"
#import "CBLJSViewCompiler.h"
#import <Security/Security.h>

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
        bundleID = @"com.couchbase.LiteServ";

    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                         NSUserDomainMask, YES);
    NSString* path = paths[0];
    path = [path stringByAppendingPathComponent: bundleID];
    path = [path stringByAppendingPathComponent: @"CouchbaseLite"];
    NSError* error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath: path
                                  withIntermediateDirectories: YES
                                                   attributes: nil error: &error]) {
        NSLog(@"FATAL: Couldn't create CouchbaseLite server dir at %@", path);
        exit(1);
    }
    return path;
}


static bool doReplicate(CBLManager* dbm, const char* replArg,
                        BOOL pull, BOOL createTarget, BOOL continuous,
                        const char *user, const char *password, const char *realm)
{
    NSURL* remote = CFBridgingRelease(CFURLCreateWithBytes(NULL, (const UInt8*)replArg,
                                                           strlen(replArg),
                                                           kCFStringEncodingUTF8, NULL));
    if (!remote || !remote.scheme) {
        fprintf(stderr, "Invalid remote URL <%s>\n", replArg);
        return false;
    }
    NSString* dbName = remote.lastPathComponent;
    if (dbName.length == 0) {
        fprintf(stderr, "Invalid database name '%s'\n", dbName.UTF8String);
        return false;
    }

    if (user && password) {
        NSString* userStr = @(user);
        NSString* passStr = @(password);
        NSString* realmStr = realm ? @(realm) : nil;
        Log(@"Setting session credentials for user '%@' in realm %@", userStr, realmStr);
        NSURLCredential* cred;
        cred = [NSURLCredential credentialWithUser: userStr
                                          password: passStr
                                       persistence: NSURLCredentialPersistenceForSession];
        int port = remote.port.intValue;
        if (port == 0)
            port = [remote.scheme isEqualToString: @"https"] ? 443 : 80;
        NSURLProtectionSpace* space;
        space = [[NSURLProtectionSpace alloc] initWithHost: remote.host
                                                      port: port
                                                  protocol: remote.scheme
                                                     realm: realmStr
                                      authenticationMethod: NSURLAuthenticationMethodDefault];
        [[NSURLCredentialStorage sharedCredentialStorage] setDefaultCredential: cred
                                                            forProtectionSpace: space];
    }

    if (pull)
        Log(@"Pulling from <%@> --> %@ ...", remote, dbName);
    else
        Log(@"Pushing %@ --> <%@> ...", dbName, remote);

    // Actually replicate -- this could probably be cleaned up to use the public API.
    CBL_Replicator* repl = nil;
    NSError* error = nil;
    CBLDatabase* db = [dbm existingDatabaseNamed: dbName error: &error];
    if (pull) {
        // Pull always deletes the local db, since it's used for testing the replicator.
        if (db) {
            if (![db deleteDatabase: &error]) {
                fprintf(stderr, "Couldn't delete existing database '%s': %s\n",
                        dbName.UTF8String, error.localizedDescription.UTF8String);
                return false;
            }
        }
        db = [dbm databaseNamed: dbName error: &error];
    }
    if (db && ![db open: &error])
        db = nil;
    if (!db) {
        fprintf(stderr, "Couldn't open database '%s': %s\n",
                dbName.UTF8String, error.localizedDescription.UTF8String);
        return false;
    }
    repl = [[CBL_Replicator alloc] initWithDB: db remote: remote push: !pull
                                   continuous: continuous];
    if (createTarget && !pull)
        ((CBL_Pusher*)repl).createTarget = YES;
    if (!repl)
        fprintf(stderr, "Unable to create replication.\n");
    [repl start];

    return true;
}


static void usage(void) {
    fprintf(stderr, "USAGE: LiteServ\n"
            "\t[--dir <databaseDir>]    Alternate directory to store databases in\n"
            "\t[--port <listeningPort>] Port to listen on (defaults to 59840)\n"
            "\t[--<readonly>]           Enables read-only mode\n"
            "\t[--auth]                 REST API requires HTTP auth\n"
            "\t[--pull <URL>]           Pull from remote database\n"
            "\t[--push <URL>]           Push to remote database\n"
            "\t[--create-target]        Create replication target database\n"
            "\t[--continuous]           Continuous replication\n"
            "\t[--user <username>]      Username for connecting to remote database\n"
            "\t[--password <password>]  Password for connecting to remote database\n"
            "\t[--realm <realm>]        HTTP realm for connecting to remote database\n"
            "\t[--ssl <identityname>]   Identity pref name to use for SSL serving\n"
            "Runs Couchbase Lite as a faceless server.\n");
}


int main (int argc, const char * argv[])
{
    @autoreleasepool {
#if DEBUG
        EnableLog(YES);
        EnableLogTo(CBLListener, YES);
#endif

        [CBLView setCompiler: [[CBLJSViewCompiler alloc] init]];

        NSString* dataPath = nil;
        UInt16 port = kPortNumber;
        CBLManagerOptions options = {};
        const char* replArg = NULL, *user = NULL, *password = NULL, *realm = NULL;
        const char* identityName = NULL;
        BOOL auth = NO, pull = NO, createTarget = NO, continuous = NO;

        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--help") == 0) {
                usage();
                return 1;
            } else if (strcmp(argv[i], "--dir") == 0) {
                const char *path = argv[++i];
                dataPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: path
                                                                           length: strlen(path)];
            } else if (strcmp(argv[i], "--port") == 0) {
                const char *str = argv[++i];
                char *end;
                port = (UInt16)strtol(str, &end, 10);
            } else if (strcmp(argv[i], "--readonly") == 0) {
                options.readOnly = YES;
            } else if (strcmp(argv[i], "--auth") == 0) {
                auth = YES;
            } else if (strcmp(argv[i], "--pull") == 0) {
                replArg = argv[++i];
                pull = YES;
            } else if (strcmp(argv[i], "--push") == 0) {
                replArg = argv[++i];
            } else if (strcmp(argv[i], "--create-target") == 0) {
                createTarget = YES;
            } else if (strcmp(argv[i], "--continuous") == 0) {
                continuous = YES;
            } else if (strcmp(argv[i], "--user") == 0) {
                user = argv[++i];
            } else if (strcmp(argv[i], "--password") == 0) {
                password = argv[++i];
            } else if (strcmp(argv[i], "--realm") == 0) {
                realm = argv[++i];
            } else if (strcmp(argv[i], "--ssl") == 0) {
                identityName = argv[++i];
            } else if (strncmp(argv[i], "-Log", 4) == 0) {
                ++i; // Ignore MYUtilities logging flags
            } else {
                fprintf(stderr, "Unknown option '%s'\n", argv[i]);
                usage();
                return 1;
            }
        }

        if (dataPath == nil)
            dataPath = GetServerPath();

        NSError* error;
        CBLManager* server = [[CBLManager alloc] initWithDirectory: dataPath
                                                           options: &options
                                                             error: &error];
        if (error) {
            Warn(@"FATAL: Error initializing CouchbaseLite: %@", error);
            exit(1);
        }

        // Start a listener socket:
        CBLListener* listener = [[CBLListener alloc] initWithManager: server port: port];
        NSCAssert(listener!=nil, @"Coudln't create CBLListener");
        listener.readOnly = options.readOnly;

        if (auth) {
            srandomdev();
            NSString* password = [NSString stringWithFormat: @"%lx", random()];
            listener.passwords = @{@"cbl": password};
            Log(@"Auth required: user='cbl', password='%@'", password);
        }

        if (identityName) {
            NSString* name = [NSString stringWithUTF8String: identityName];
            SecIdentityRef identity = SecIdentityCopyPreferred((__bridge CFStringRef)name, NULL, NULL);
            if (!identity) {
                Warn(@"FATAL: Couldn't find identity pref named '%@'", name);
                exit(1);
            }
            Log(@"Serving SSL with %@", identity);
            listener.SSLIdentity = identity;
            CFRelease(identity);
        }

        // Advertise via Bonjour, and set a TXT record just as an example:
        [listener setBonjourName: @"LiteServ" type: @"_cbl._tcp."];
        NSData* value = [@"value" dataUsingEncoding: NSUTF8StringEncoding];
        listener.TXTRecordDictionary = @{@"Key": value};

        if (![listener start: &error]) {
            Warn(@"Failed to start HTTP listener: %@", error.localizedDescription);
            exit(1);
        }

        if (replArg) {
            if (!doReplicate(server, replArg, pull, createTarget, continuous, user, password, realm))
                return 1;
        } else {
            Log(@"LiteServ %@ is listening%@ at <%@> ... relax!",
                CBLVersionString(),
                (listener.readOnly ? @" in read-only mode" : @""),
                listener.URL);
        }

        [[NSRunLoop currentRunLoop] run];

        Log(@"LiteServ quitting");
    }
    return 0;
}

