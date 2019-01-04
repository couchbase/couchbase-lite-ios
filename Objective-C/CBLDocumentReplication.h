//
//  CBLDocumentReplication.h
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
#import "CBLDocumentFlags.h"
@class CBLReplicator;
@class CBLReplicatedDocument;

NS_ASSUME_NONNULL_BEGIN

/** Document replication event */
@interface CBLDocumentReplication : NSObject

/** The replicator. */
@property (nonatomic, readonly) CBLReplicator* replicator;

/** The flag indicating that the replication is push or pull. */
@property (nonatomic, readonly) BOOL isPush;

/** A list of the replicated documents. */
@property (nonatomic, readonly) NSArray<CBLReplicatedDocument*>* documents;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

/// CBLReplicatedDocument contains the information of a document that has been replicated.
@interface CBLReplicatedDocument : NSObject

/** The document ID. */
@property (nonatomic, readonly) NSString* id;

/** The flags describing the replicated document. */
@property (nonatomic, readonly) CBLDocumentFlags flags;

/** The error if occurred */
@property (nonatomic, readonly, nullable) NSError* error;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
