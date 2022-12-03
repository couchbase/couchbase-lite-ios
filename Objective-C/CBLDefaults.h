//
//  CBLDefaults.h
//  CouchbaseLite
//
//  Copyright (c) 2022-present Couchbase, Inc All rights reserved.
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

// THIS IS AN AUTOGENERATED FILE, MANUAL CHANGES SHOULD BE EXPECTED TO
// BE OVERWRITTEN

#import "CBLReplicatorTypes.h"

#pragma mark - CBLLogFileConfiguration

/** [NO] Plaintext is not used, and instead binary encoding is used in log files */
extern const BOOL kCBLDefaultLogFileUsePlainText;

/** [524288] 512 KiB for the size of a log file */
extern const uint64_t kCBLDefaultLogFileMaxSize;

/** [1] 1 rotated file present (2 total, including the currently active log file) */
extern const NSInteger kCBLDefaultLogFileMaxRotateCount;

#pragma mark - CBLFullTextIndexConfiguration

/** [NO] Accents and ligatures are not ignored when indexing via full text search */
extern const BOOL kCBLDefaultFullTextIndexIgnoreAccents;

#pragma mark - CBLReplicatorConfiguration

/** [kCBLReplicatorTypePushAndPull] Perform bidirectional replication */
extern const CBLReplicatorType kCBLDefaultReplicatorType;

/** [NO] One-shot replication is used, and will stop once all initial changes are processed */
extern const BOOL kCBLDefaultReplicatorContinuous;

/** [NO] Replication stops when an application enters background mode */
extern const BOOL kCBLDefaultReplicatorAllowReplicatingInBackground;

/** [300] A heartbeat messages is sent every 300 seconds to keep the connection alive */
extern const NSTimeInterval kCBLDefaultReplicatorHeartbeat;

/** [10] When replicator is not continuous, after 10 failed attempts give up on the replication */
extern const NSUInteger kCBLDefaultReplicatorMaxAttemptsSingleShot;

/** [NSUIntegerMax] When replicator is continuous, never give up unless explicitly stopped */
extern const NSUInteger kCBLDefaultReplicatorMaxAttemptsContinuous;

/** [300] Max wait time between retry attempts in seconds */
extern const NSTimeInterval kCBLDefaultReplicatorMaxAttemptWaitTime;

/** [YES] Purge documents when a user loses access */
extern const BOOL kCBLDefaultReplicatorEnableAutoPurge;

/** [NO] Whether or not a replicator only accepts self-signed certificates from the remote */
extern const BOOL kCBLDefaultReplicatorSelfSignedCertificateOnly;

#pragma mark - CBLURLEndpointListenerConfiguration

/** [0] No port specified, the OS will assign one */
extern const unsigned short kCBLDefaultListenerPort;

/** [NO] TLS is enabled on the connection */
extern const BOOL kCBLDefaultListenerDisableTls;

/** [NO] The listener will allow database writes */
extern const BOOL kCBLDefaultListenerReadOnly;

/** [NO] Delta sync is disabled for the listener */
extern const BOOL kCBLDefaultListenerEnableDeltaSync;


