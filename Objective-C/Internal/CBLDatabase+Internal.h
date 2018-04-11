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
#import "Fleece.h"
#import "CBLBlob.h"
#import "CBLDatabase.h"
#import "CBLDatabaseConfiguration.h"
#import "CBLDatabaseChange.h"
#import "CBLMutableDocument.h"
#import "CBLDocumentChange.h"
#import "CBLJSONCoding.h"
#import "CBLReplicator.h"
#import "CBLLiveQuery.h"

#ifdef COUCHBASE_ENTERPRISE
#import "CBLEncryptionKey.h"
#endif

struct c4BlobStore;

@class CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN


/// CBLDatabase:


@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (readonly, nonatomic) dispatch_queue_t queryQueue;
@property (readonly, nonatomic) NSMapTable<NSURL*,CBLReplicator*>* replications;
@property (readonly, nonatomic) NSMutableSet<CBLReplicator*>* activeReplications;
@property (readonly, nonatomic) NSMutableSet<CBLLiveQuery*>* liveQueries;
@property (readonly, nonatomic) FLSharedKeys sharedKeys;

- (void) mustBeOpen;
- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;
- (bool) resolveConflictInDocument: (NSString*)docID error: (NSError**)outError;

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


@interface CBLBlob () <CBLJSONCoding>

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
