//
//  CBLLogTypes.h
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

/** Log domain options. */
typedef NS_OPTIONS(NSUInteger, CBLLogDomain) {
    kCBLLogDomainDatabase       = 1 << 0,       ///< Database domain.
    kCBLLogDomainQuery          = 1 << 1,       ///< Query domain.
    kCBLLogDomainReplicator     = 1 << 2,       ///< Replicator domain.
    kCBLLogDomainNetwork        = 1 << 3,       ///< Network domain.
    kCBLLogDomainListener       = 1 << 4,       ///< Listener domain.
    kCBLLogDomainPeerDiscovery  = 1 << 5,       ///< Peer Discovery domain.
    kCBLLogDomainMDNS           = 1 << 6,       ///< mDNS specific logs used for DNS-SD peer discovery
    kCBLLogDomainMultipeer      = 1 << 9,       ///< Multipeer Replication domain.
    kCBLLogDomainAll            = (1 << 10) - 1 ///< All domains
};

/** Log level. */
typedef NS_ENUM(NSUInteger, CBLLogLevel) {
    kCBLLogLevelDebug,      ///< Debug log messages. Only present in debug builds of CouchbaseLite.
    kCBLLogLevelVerbose,    ///< Verbose log messages.
    kCBLLogLevelInfo,       ///< Informational log messages.
    kCBLLogLevelWarning,    ///< Warning log messages.
    kCBLLogLevelError,      ///< Error log messages.
    kCBLLogLevelNone        ///< Disabling log messages of a given log domain.
};

NS_ASSUME_NONNULL_END
