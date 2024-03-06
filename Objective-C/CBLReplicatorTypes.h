//
//  CBLReplicatorTypes.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
#import <CouchbaseLite/CBLDocumentFlags.h>

@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/** Activity level of a replicator. */
typedef enum {
    kCBLReplicatorStopped,    ///< The replicator is finished or hit a fatal error.
    kCBLReplicatorOffline,    ///< The replicator is offline as the remote host is unreachable.
    kCBLReplicatorConnecting, ///< The replicator is connecting to the remote host.
    kCBLReplicatorIdle,       ///< The replicator is inactive waiting for changes or offline.
    kCBLReplicatorBusy        ///< The replicator is actively transferring data.
} CBLReplicatorActivityLevel;

/**
 Progress of a replicator. If `total` is zero, the progress is indeterminate; otherwise,
 dividing the two will produce a fraction that can be used to draw a progress bar. */
typedef struct {
    uint64_t completed; ///< The number of completed changes processed.
    uint64_t total;     ///< The total number of changes to be processed.
} CBLReplicatorProgress;

/** Replicator type. */
typedef NS_ENUM(NSUInteger, CBLReplicatorType) {
    kCBLReplicatorTypePushAndPull = 0,              ///< Bidirectional; both push and pull
    kCBLReplicatorTypePush,                         ///< Pushing changes to the target
    kCBLReplicatorTypePull                          ///< Pulling changes from the target
};

/** Replication Filter */
typedef BOOL (^CBLReplicationFilter) (CBLDocument* document, CBLDocumentFlags flags);

NS_ASSUME_NONNULL_END
