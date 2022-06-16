//
//  CBLDatabase+Internal.h
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

#pragma once
#import "c4.h"
#import "fleece/Fleece.h"
#import "CBLBlob.h"
#import "CBLDatabase.h"
#import "CBLDatabaseConfiguration.h"
#import "CBLDatabaseChange.h"
#import "CBLMutableDocument.h"
#import "CBLDocumentChange.h"
#import "CBLReplicator.h"
#import "CBLConflictResolver.h"
#import "CBLStoppable.h"
#import "CBLLockable.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLEncryptionKey.h"
#import "CBLURLEndpointListener.h"
#endif

#define msec 1000.0

struct c4BlobStore;

@class CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN


/// CBLDatabase:


@interface CBLDatabase () <CBLLockable>

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (readonly, nonatomic) dispatch_queue_t queryQueue;
@property (readonly, nonatomic) FLSharedKeys sharedKeys;

- (void) mustBeOpenLocked;
- (BOOL) isClosedLocked;

- (C4SliceResult) getPublicUUID: (NSError**)outError;

- (nullable C4BlobStore*) getBlobStore: (NSError**)outError;

- (void) addActiveStoppable: (id<CBLStoppable>)stoppable;
- (void) removeActiveStoppable: (id<CBLStoppable>)stoppable;
- (uint64_t) activeStoppableCount; // For testing only

- (bool) resolveConflictInDocument: (NSString*)docID
              withConflictResolver: (nullable id<CBLConflictResolver>)conflictResolver
                             error: (NSError**)outError;

// Initialize the CBLDatabase with a give C4Database object in the shell mode.
// This is currently used for creating a CBLDictionary as an input of the predict()
// method of the PredictiveModel.
- (instancetype) initWithC4Database: (C4Database*)c4db;

- (nullable NSString*) getCookies: (NSURL*)url error: (NSError**)error;
- (BOOL) saveCookie: (NSString*)cookie url: (NSURL*)url;

// Gets called from CBLCollection as well. Must be called inside a lock
- (BOOL) prepareDocument: (CBLDocument*)document error: (NSError**)error;

@end

/// CBLDatabaseConfiguration:


@interface CBLDatabaseConfiguration ()

#ifdef COUCHBASE_ENTERPRISE
@property (nonatomic, nullable) CBLEncryptionKey* encryptionKey;
#endif

- (instancetype) initWithConfig: (nullable CBLDatabaseConfiguration*)config
                       readonly: (BOOL)readonly;

+ (NSString*) defaultDirectory;

@end


// CBLBlob:


@interface CBLBlob ()

- (instancetype) initWithProperties: (NSDictionary *)properties;

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


// CBLDocumentChange:

@interface CBLDocumentChange ()

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID;

@end


// CBLDatabaseChange:

@interface CBLDatabaseChange ()

/** check whether the changes are from the current database object or not. */
@property (readonly, nonatomic) BOOL isExternal;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                      documentIDs: (NSArray*)documentIDs
                       isExternal: (BOOL)isExternal;

@end


NS_ASSUME_NONNULL_END
