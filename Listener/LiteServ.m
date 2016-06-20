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
#import "CBLListener.h"
#import "CBLRestReplicator.h"
#import "CBLManager+Internal.h"
#import "CBLDatabase+Replication.h"
#import "CBLMisc.h"
#import "CBLRegisterJSViewCompiler.h"
#import "CBLSyncListener.h"
#import <Security/Security.h>

#import "MYLogging.h"
#import "MYErrorUtils.h"


#define kPortNumber 59840


@interface ListenerDelegate : NSObject <CBLListenerDelegate>
@end


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
        Warn(@"FATAL: Couldn't create CouchbaseLite server dir at %@", path);
        exit(1);
    }
    return path;
}


static NSString* MakeAbsolutePath(const char *cStr) {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    NSString* path = [fmgr stringWithFileSystemRepresentation: cStr length: strlen(cStr)];
    if (path && !path.isAbsolutePath)
        path = [fmgr.currentDirectoryPath stringByAppendingPathComponent: path];
    return path.stringByStandardizingPath;
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
        AlwaysLog(@"Pulling from <%@> --> %@ ...", remote, dbName);
    else
        AlwaysLog(@"Pushing %@ --> <%@> ...", dbName, remote);

    // Actually replicate -- this could probably be cleaned up to use the public API.
    id<CBL_Replicator> repl = nil;
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
    if (!db) {
        fprintf(stderr, "Couldn't open database '%s': %s\n",
                dbName.UTF8String, error.localizedDescription.UTF8String);
        return false;
    }

    CBL_ReplicatorSettings* settings = [[CBL_ReplicatorSettings alloc] initWithRemote: remote
                                                                                 push: !pull];
    settings.continuous = continuous;
    if (createTarget && !pull)
        settings.createTarget = YES;

    repl = [[CBLRestReplicator alloc] initWithDB: db settings: settings];
    if (!repl)
        fprintf(stderr, "Unable to create replication.\n");

    [[NSNotificationCenter defaultCenter] addObserverForName: nil object: repl queue: nil
                                                  usingBlock:^(NSNotification* n)
    {
        if ([n.name isEqualToString: CBL_ReplicatorProgressChangedNotification]) {
            Log(@"*** Replicator status changed ***");
        } else if ([n.name isEqualToString: CBL_ReplicatorStoppedNotification]) {
            if (repl.error)
                AlwaysLog(@"*** Replicator failed, error = %@", repl.error.my_compactDescription);
            else
                AlwaysLog(@"*** Replicator finished ***");
        } else {
            Log(@"*** Replicator posted %@", n.name);
        }
    }];

    [repl start];
    return true;
}


static void usage(void) {
    fprintf(stderr, "USAGE: LiteServ\n"
            "\t[--dir <databaseDir>]    Alternate directory to store databases in\n"
            "\t[--port <listeningPort>] Port to listen on (defaults to 59840)\n"
            "\t[--readonly]             Enables read-only mode\n"
            "\t[--auth]                 REST API requires HTTP auth\n"
            "\t[--pull <URL>]           Pull from remote database\n"
            "\t[--push <URL>]           Push to remote database\n"
            "\t[--create-target]        Create replication target database\n"
            "\t[--continuous]           Continuous replication\n"
            "\t[--user <username>]      Username for connecting to remote database\n"
            "\t[--password <password>]  Password for connecting to remote database\n"
            "\t[--realm <realm>]        HTTP realm for connecting to remote database\n"
            "\t[--revs_limit <n>        Sets default max rev-tree depth for databases\n"
            "\t[--ssl]                  Serve over SSL\n"
            "\t[--sslas <identityname>] Identity pref name to use for SSL serving\n"
            "\t[--storage <engine>]     Set default storage engine: 'SQLite' or 'ForestDB'\n"
            "\t[--dbpassword <dbname>=<password>]  Register password to open a database\n"
            "Runs Couchbase Lite as a faceless server.\n");
}


CBLManagerOptions options = {};
const char* replArg = NULL, *user = NULL, *password = NULL, *realm = NULL;
const char* identityName = NULL;
BOOL auth = NO, useSSL = NO;


static void startListener(CBLListener* listener) {
    NSCAssert(listener!=nil, @"Couldn't create CBLListener");
    listener.readOnly = options.readOnly;
    
    static id<CBLListenerDelegate> delegate;
    if (!delegate)
        delegate = [[ListenerDelegate alloc] init];
    listener.delegate = delegate;

    if (auth) {
        srandomdev();
        NSString* password = [NSString stringWithFormat: @"%lx", random()];
        listener.passwords = @{@"cbl": password};
        AlwaysLog(@"Enabled HTTP auth: user='cbl', password='%@'", password);
    }

    if (useSSL) {
        NSString* name;
        if (identityName) {
            name = [NSString stringWithUTF8String: identityName];
            SecIdentityRef identity = SecIdentityCopyPreferred((__bridge CFStringRef)name, NULL, NULL);
            if (!identity) {
                Warn(@"FATAL: Couldn't find identity pref named '%@'", name);
                exit(1);
            }
            listener.SSLIdentity = identity;
            CFRelease(identity);
        } else {
            name = @"LiteServ";
            NSError* error;
            if (![listener setAnonymousSSLIdentityWithLabel: name error: &error]) {
                Warn(@"FATAL: Couldn't get/create default SSL identity: %@",
                     error.my_compactDescription);
                exit(1);
            }
        }
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            AlwaysLog(@"Serving SSL as identity '%@' %@", name, listener.SSLIdentityDigest);
        });
    }

    // Advertise via Bonjour, and set a TXT record just as an example:
    [listener setBonjourName: @"LiteServ" type: @"_cbl._tcp."];
    NSData* value = [@"value" dataUsingEncoding: NSUTF8StringEncoding];
    listener.TXTRecordDictionary = @{@"Key": value};

    NSError* error;
    if (![listener start: &error]) {
        Warn(@"Failed to start %@: %@", listener.class, error.my_compactDescription);
        exit(1);
    }
}


static long str2long(const char *str) {
    char *end;
    return strtol(str, &end, 10);
}


int main (int argc, const char * argv[])
{
    @autoreleasepool {
        CBLRegisterJSViewCompiler();

        NSString *dataPath = nil, *storageType = nil;
        UInt16 port = kPortNumber, nuPort = 0;
        BOOL pull = NO, createTarget = NO, continuous = NO;
        NSMutableDictionary* dbPasswords = [NSMutableDictionary new];
        NSUInteger maxRevTreeDepth = 0;

        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--help") == 0) {
                usage();
                return 1;
            } else if (strcmp(argv[i], "--dir") == 0) {
                dataPath = MakeAbsolutePath(argv[++i]);
            } else if (strcmp(argv[i], "--port") == 0) {
                port = (UInt16)str2long(argv[++i]);
            } else if (strcmp(argv[i], "--nuport") == 0) {
                nuPort = (UInt16)str2long(argv[++i]);
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
                useSSL = YES;
            } else if (strcmp(argv[i], "--sslas") == 0) {
                useSSL = YES;
                identityName = argv[++i];
            } else if (strcmp(argv[i], "--storage") == 0) {
                storageType = [NSString stringWithUTF8String: argv[++i]];
            } else if (strcmp(argv[i], "--dbpassword") == 0) {
                NSString *arg = [NSString stringWithUTF8String: argv[++i]];
                NSArray* items = [arg componentsSeparatedByString: @"="];
                if (items.count != 2) {
                    fprintf(stderr, "Invalid --dbpassword argument: needs to be NAME=PASSWORD\n");
                    exit(1);
                }
                dbPasswords[items[0]] = items[1];
                AlwaysLog(@"Using password for encrypted database '%@'", items[0]);
            } else if (strcmp(argv[i], "--revs_limit") == 0) {
                maxRevTreeDepth = str2long(argv[++i]);
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
            Warn(@"FATAL: Error initializing CouchbaseLite: %@", error.my_compactDescription);
            exit(1);
        }

        if (storageType)
            server.storageType = storageType;
        if (maxRevTreeDepth > 0)
            server.defaultMaxRevTreeDepth = maxRevTreeDepth;

        for (NSString* dbName in dbPasswords)
            [server registerEncryptionKey: dbPasswords[dbName] forDatabaseNamed: dbName];

        // Start a listener socket:
        CBLListener* listener = [[CBLListener alloc] initWithManager: server port: port];
        startListener(listener);

        CBLSyncListener* syncListener;
        if (nuPort > 0) {
            // New-replicator listener:
            syncListener = [[CBLSyncListener alloc] initWithManager: server port: nuPort];
            startListener(syncListener);
            AlwaysLog(@"Listening for BLIP replications at <%@>", syncListener.URL);
        }

        if (replArg) {
            if (!doReplicate(server, replArg, pull, createTarget, continuous, user, password, realm))
                return 1;
        } else {
            AlwaysLog(@"LiteServ %@ is listening%@ at <%@> ... relax!",
                CBLVersion(),
                (listener.readOnly ? @" in read-only mode" : @""),
                listener.URL);
        }

        [[NSRunLoop currentRunLoop] run];

        AlwaysLog(@"LiteServ quitting");
    }
    return 0;
}


@implementation ListenerDelegate

- (NSString*) authenticateConnectionFromAddress: (NSData*)address
                                      withTrust: (SecTrustRef)trust
{
    if (trust) {
        SecCertificateRef cert = SecTrustGetCertificateAtIndex(trust, 0);
        CFStringRef cfCommonName = NULL;
        SecCertificateCopyCommonName(cert, &cfCommonName);
        NSString* commonName = CFBridgingRelease(cfCommonName);
        Log(@"Incoming SSL connection with client cert for '%@'", commonName);
        return commonName;
    } else {
        Log(@"Incoming SSL connection without a client cert");
        return @"";
    }
}

@end
