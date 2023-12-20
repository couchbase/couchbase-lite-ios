//
//  CBLCollection+Internal.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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
#import "CBLCollection.h"
#import "CBLChangeListenerToken.h"
#import "CBLDatabase.h"

#define CBLCollectionErrorNotOpen [NSError errorWithDomain: CBLErrorDomain \
                                    code: CBLErrorNotOpen \
                                    userInfo: @{ NSLocalizedDescriptionKey: kCBLErrorMessageDBClosedOrCollectionDeleted }]

#define CBLDatabaseErrorNotOpen [NSError errorWithDomain: CBLErrorDomain \
                                    code: CBLErrorNotOpen \
                                    userInfo: @{ NSLocalizedDescriptionKey: \
                                        @"Database is not open." }]

NS_ASSUME_NONNULL_BEGIN

@interface CBLCollection () <CBLRemovableListenerToken>

/** dispatch queue */
@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;

/** The database associated with the collection. When the (internal default) collection is cached in the database,
    the database will be set to the weakdb to avoid circular retain references. */
@property (nonatomic, readonly, weak) CBLDatabase* weakdb;
@property (nonatomic, readonly, nullable) CBLDatabase* strongdb;

@property (nonatomic, readonly) BOOL isValid;

@property (nonatomic, readonly) C4Collection* c4col;

@property (nonatomic, readonly) C4CollectionSpec c4spec;

/** The cached mode indicates that the collection object will be cached in the database or not.
    When the collection is cached, the collection will not retain the database inside
    the collection object to avoid the circular refererences. */
- (instancetype) initWithDB: (CBLDatabase*)db
               c4collection: (C4Collection*)c4collection
                     cached: (BOOL)cached;

- (bool) resolveConflictInDocument: (NSString*)docID
              withConflictResolver: (nullable id<CBLConflictResolver>)conflictResolver
                             error: (NSError**)outError;

- (BOOL) checkIsValid: (NSError**)error;

@end

@interface CBLCollectionChange ()

/** check whether the changes are from the current collection or not. */
@property (readonly, nonatomic) BOOL isExternal;

- (instancetype) initWithCollection: (CBLCollection*)collection
                        documentIDs: (NSArray*)documentIDs
                         isExternal: (BOOL)isExternal;

@end

NS_ASSUME_NONNULL_END
