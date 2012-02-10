//
//  TDServer.m
//  TouchDB
//
//  Created by Jens Alfke on 11/30/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDServer.h"
#import "TDDatabase.h"
#import "TDInternal.h"


@implementation TDServer


#define kDBExtension @"touchdb"

// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [TDServer class]) {
        kIllegalNameChars = [[[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                                        invertedSet] retain];
    }
}


#if DEBUG
+ (TDServer*) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: nil];
    NSError* error;
    TDServer* server = [[self alloc] initWithDirectory: path error: &error];
    Assert(server, @"Failed to create server at %@: %@", path, error);
    AssertEqual(server.directory, path);
    return [server autorelease];
}
+ (TDServer*) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}

#endif


- (id) initWithDirectory: (NSString*)dirPath error: (NSError**)outError {
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _dir = [dirPath copy];
        _databases = [[NSMutableDictionary alloc] init];
        
        // Create the directory but don't fail if it already exists:
        NSError* error;
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                       withIntermediateDirectories: NO
                                                        attributes: nil
                                                             error: &error]) {
            if (!$equal(error.domain, NSCocoaErrorDomain)
                        || error.code != NSFileWriteFileExistsError) {
                if (outError) *outError = error;
                [self release];
                return nil;
            }
        }
    }
    return self;
}

- (void)dealloc {
    [self close];
    [_dir release];
    [_databases release];
    [super dealloc];
}

@synthesize directory = _dir;

- (NSString*) pathForName: (NSString*)name {
    if (name.length == 0 || [name rangeOfCharacterFromSet: kIllegalNameChars].length > 0
                         || !islower([name characterAtIndex: 0]))
        return nil;
    name = [name stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [_dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:kDBExtension]];
}

- (TDDatabase*) databaseNamed: (NSString*)name create: (BOOL)create {
    TDDatabase* db = [_databases objectForKey: name];
    if (!db) {
        NSString* path = [self pathForName: name];
        if (!path)
            return nil;
        db = [[TDDatabase alloc] initWithPath: path];
        if (!create && !db.exists) {
            [db release];
            return nil;
        }
        db.name = name;
        [_databases setObject: db forKey: name];
        [db release];
    }
    return db;
}

- (TDDatabase*) databaseNamed: (NSString*)name {
    return [self databaseNamed: name create: YES];
}

- (TDDatabase*) existingDatabaseNamed: (NSString*)name {
    TDDatabase* db = [self databaseNamed: name create: NO];
    if (db && ![db open])
        db = nil;
    return db;
}

- (BOOL) deleteDatabaseNamed: (NSString*)name {
    TDDatabase* db = [self databaseNamed: name];
    if (!db)
        return NO;
    [db deleteDatabase: NULL];
    [_databases removeObjectForKey: name];
    return YES;
}


- (NSArray*) allDatabaseNames {
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _dir error: nil];
    files = [files pathsMatchingExtensions: $array(kDBExtension)];
    return [files my_map: ^(id filename) {
        return [[filename stringByDeletingPathExtension]
                                stringByReplacingOccurrencesOfString: @":" withString: @"/"];
    }];
}


- (NSArray*) allOpenDatabases {
    return _databases.allValues;
}


- (void) close {
    for (TDDatabase* db in _databases.allValues) {
        [db close];
    }
    [_databases removeAllObjects];
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(TDServer) {
    RequireTestCase(TDDatabase);
    TDServer* server = [TDServer createEmptyAtTemporaryPath: @"TDServerTest"];
    TDDatabase* db = [server databaseNamed: @"foo"];
    CAssert(db != nil);
    CAssertEqual(db.name, @"foo");
    CAssertEqual(db.path.stringByDeletingLastPathComponent, server.directory);
    CAssert(!db.exists);
    
    CAssertEq([server databaseNamed: @"foo"], db);
    
    CAssertEqual(server.allDatabaseNames, $array());    // because foo doesn't exist yet
    
    CAssert([db open]);
    CAssert(db.exists);
    CAssertEqual(server.allDatabaseNames, $array(@"foo"));    // because foo doesn't exist yet
}

#endif
