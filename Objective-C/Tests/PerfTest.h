//
//  PerfTest.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import <CouchbaseLite/CouchbaseLite.h>

#ifdef __cplusplus
extern "C" {
#endif

#import "Test.h"

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_BEGIN


/** Couchbase Lite performance test abstract base class. */
@interface PerfTest : NSObject

/** Specifies the filesystem path of the directory where resource/fixture files are located.
    If not called, resources are assumed to be in the Resources directory of the bundle containing
    the test class. */
+ (void) setResourceDirectory: (NSString*)resourceDir;

/** A default database configuration to use; puts the databases in a subdirectory of the system
     temporary directory, named "CouchbaseLite". */
+ (CBLDatabaseConfiguration*) defaultConfig;

/** Runs an instance of this test, with the given database configuration. */
+ (void) runWithConfig: (nullable CBLDatabaseConfiguration*)config;

/** Initializer; you probably won't need to call or override this. */
- (instancetype) initWithDatabaseConfig: (nullable CBLDatabaseConfiguration*)dbConfig;

/** The database to work with. Starts out empty on every run. */
@property (readonly, nonatomic) CBLDatabase* db;

/** Closes the database and reopens it. */
- (void) reopenDB;

/** Closes and deletes the database. The next call to `db` or `reopenDB` will recreate it, empty. */
- (void) eraseDB;

/** Loads the contents of a file located in the resource directory. */
- (NSData*) dataFromResource: (NSString*)resourceName ofType: (NSString*)type;

/** Runs the block ten times, timing each iteration, and logs a report.
    @param count  The number of units of work (of some sort) performed by the block each time
    @param unitName  The name of this unit of work, to be included in the report.
    @param block  The block of code to be timed. */
- (void) measureAtScale: (NSUInteger)count unit: (NSString*)unitName block: (void (^)(void))block;

/** Called at the start of each test, before the `test` method.
     Override this to initialize or load any state that shouldn't be timed.
     Call [super setup] first. */
- (void) setUp;

/** The main body of the test. You MUST override this. Do not call the superclass method. */
- (void) test;

/** Called at the end of each test, after the `test` method.
     You can override this to clean up any otherwise-persistent state.
     Call `[super tearDown]` at the end of your method. */
- (void) tearDown;

/** Runs a test by invoking -setUp, -test, and -tearDown in sequence. */
- (void) run;

@end

NS_ASSUME_NONNULL_END
