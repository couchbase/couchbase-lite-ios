//
//  CBLDatabaseConfiguration.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLDatabaseConfiguration : NSObject

/**
 Path to the directory to store the database in. If the directory doesn't already exist it will
 be created when the database is opened. The default directory will be in Application Support.
 You won't usually need to change this.
 */
@property (nonatomic, copy) NSString* directory;

/**
 Experiment API. Enable version vector.
 
 If the enableVersionVector is set to true, the database will use version vector instead of
 using revision tree. When enabling version vector on an existing database, the database
 will be upgraded to use the revision tree while the database is opened.
 
 NOTE:
 1. The database that uses version vector cannot be downgraded back to use revision tree.
 2. The current version of Sync Gateway doesn't support version vector so the syncronization
 with Sync Gateway will not be working.
 */
@property (nonatomic) BOOL enableVersionVector;

/**
 Initializes the CBLDatabaseConfiguration object.
 */
- (instancetype) init;


/**
 Initializes the CBLDatabaseConfiguration object with the configuration object.

 @param config The configuration object.
 @return The CBLDatabaseConfiguration object.
 */
- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config;

@end

NS_ASSUME_NONNULL_END
