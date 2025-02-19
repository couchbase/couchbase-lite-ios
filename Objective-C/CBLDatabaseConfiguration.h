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
 As Couchbase Lite normally configures its databases, there is a very
 small (though non-zero) chance that a power failure at just the wrong
 time could cause the most recently committed transaction's changes to
 be lost. This would cause the database to appear as it did immediately
 before that transaction.
 
 Setting this mode true ensures that an operating system crash or
 power failure will not cause the loss of any data. FULL synchronous
 is very safe but it is also dramatically slower.
 */
@property (nonatomic) BOOL fullSync;

/**
 Enables or disables memory-mapped I/O. By default, memory-mapped I/O is enabled.
 Disabling it may affect database performance. Typically, there is no need to modify this setting.

 @note: Memory-mapped I/O is always disabled to prevent database corruption on macOS.
 As a result, setting this configuration has no effect on the macOS platform.
 */
@property (nonatomic) BOOL mmapEnabled;

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
