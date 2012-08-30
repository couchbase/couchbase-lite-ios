//
//  TDDatabaseManager.m
//  TouchDB
//
//  Created by Jens Alfke on 3/22/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDDatabaseManager.h"
#import <TouchDB/TDDatabase.h>
#import "TDReplicatorManager.h"
#import "TDInternal.h"
#import "TDMisc.h"


const TDDatabaseManagerOptions kTDDatabaseManagerDefaultOptions;


@implementation TDDatabaseManager


#define kDBExtension @"touchdb"

// http://wiki.apache.org/couchdb/HTTP_database_API#Naming_and_Addressing
#define kLegalChars @"abcdefghijklmnopqrstuvwxyz0123456789_$()+-/"
static NSCharacterSet* kIllegalNameChars;

+ (void) initialize {
    if (self == [TDDatabaseManager class]) {
        kIllegalNameChars = [[[NSCharacterSet characterSetWithCharactersInString: kLegalChars]
                                        invertedSet] retain];
    }
}


#if DEBUG
+ (TDDatabaseManager*) createEmptyAtPath: (NSString*)path {
    [[NSFileManager defaultManager] removeItemAtPath: path error: NULL];
    NSError* error;
    TDDatabaseManager* dbm = [[self alloc] initWithDirectory: path
                                                     options: NULL
                                                       error: &error];
    Assert(dbm, @"Failed to create db manager at %@: %@", path, error);
    AssertEqual(dbm.directory, path);
    return [dbm autorelease];
}

+ (TDDatabaseManager*) createEmptyAtTemporaryPath: (NSString*)name {
    return [self createEmptyAtPath: [NSTemporaryDirectory() stringByAppendingPathComponent: name]];
}
#endif


- (id) initWithDirectory: (NSString*)dirPath
                 options: (const TDDatabaseManagerOptions*)options
                   error: (NSError**)outError
{
    if (outError) *outError = nil;
    self = [super init];
    if (self) {
        _dir = [dirPath copy];
        _databases = [[NSMutableDictionary alloc] init];
        _options = options ? *options : kTDDatabaseManagerDefaultOptions;
        
        // Create the directory but don't fail if it already exists:
        NSError* error;
        if (![[NSFileManager defaultManager] createDirectoryAtPath: _dir
                                       withIntermediateDirectories: NO
                                                        attributes: nil
                                                             error: &error]) {
            if (!TDIsFileExistsError(error)) {
                if (outError) *outError = error;
                [self release];
                return nil;
            }
        }
    }
    return self;
}


- (void)dealloc {
    LogTo(TDServer, @"DEALLOC %@", self);
    [self close];
    [_dir release];
    [_databases release];
    [super dealloc];
}


@synthesize directory = _dir;


#pragma mark - DATABASES:


+ (BOOL) isValidDatabaseName: (NSString*)name {
    if (name.length > 0 && [name rangeOfCharacterFromSet: kIllegalNameChars].length == 0
                        && islower([name characterAtIndex: 0]))
        return YES;
    return $equal(name, kTDReplicatorDatabaseName);
}


- (NSString*) pathForName: (NSString*)name {
    if (![[self class] isValidDatabaseName: name])
        return nil;
    name = [name stringByReplacingOccurrencesOfString: @"/" withString: @":"];
    return [_dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:kDBExtension]];
}


- (TDDatabase*) databaseNamed: (NSString*)name create: (BOOL)create {
    if (_options.readOnly)
        create = NO;
    TDDatabase* db = _databases[name];
    if (!db) {
        NSString* path = [self pathForName: name];
        if (!path)
            return nil;
        db = [[TDDatabase alloc] initWithPath: path];
        db.readOnly = _options.readOnly;
        if (!create && !db.exists) {
            [db release];
            return nil;
        }
        db.name = name;
        _databases[name] = db;
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
    NSArray* files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath: _dir error: NULL];
    files = [files pathsMatchingExtensions: @[kDBExtension]];
    return [files my_map: ^(id filename) {
        return [[filename stringByDeletingPathExtension]
                                stringByReplacingOccurrencesOfString: @":" withString: @"/"];
    }];
}


- (NSArray*) allOpenDatabases {
    return _databases.allValues;
}


- (void) close {
    LogTo(TDServer, @"CLOSE %@", self);
    [_replicatorManager stop];
    [_replicatorManager release];
    _replicatorManager = nil;
    for (TDDatabase* db in _databases.allValues) {
        [db close];
    }
    [_databases removeAllObjects];
}


- (TDReplicatorManager*) replicatorManager {
    if (!_replicatorManager && !_options.noReplicator) {
        _replicatorManager = [[TDReplicatorManager alloc] initWithDatabaseManager: self];
        [_replicatorManager start];
    }
    return _replicatorManager;
}


@end




#pragma mark - TESTS
#if DEBUG

TestCase(TDDatabaseManager) {
    RequireTestCase(TDDatabase);
    TDDatabaseManager* dbm = [TDDatabaseManager createEmptyAtTemporaryPath: @"TDDatabaseManagerTest"];
    TDDatabase* db = [dbm databaseNamed: @"foo"];
    CAssert(db != nil);
    CAssertEqual(db.name, @"foo");
    CAssertEqual(db.path.stringByDeletingLastPathComponent, dbm.directory);
    CAssert(!db.exists);
    
    CAssertEq([dbm databaseNamed: @"foo"], db);
    
    CAssertEqual(dbm.allDatabaseNames, @[]);    // because foo doesn't exist yet
    
    CAssert([db open]);
    CAssert(db.exists);
    CAssertEqual(dbm.allDatabaseNames, @[@"foo"]);    // because foo doesn't exist yet
}

#endif
