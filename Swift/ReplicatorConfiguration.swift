//
//  ReplicatorConfiguration.swift
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

import Foundation

///  Replicator type.
///
/// - pushAndPull: Bidirectional; both push and pull
/// - push: Pushing changes to the target
/// - pull: Pulling changes from the target
public enum ReplicatorType: UInt8 {
    case pushAndPull = 0
    case push
    case pull
}

/// Document flags describing a replicated document.
public struct DocumentFlags: OptionSet {
    
    /// Raw value.
    public let rawValue: Int
    
    /// Constructor with the raw value.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Indicating that the replicated document has been deleted.
    public static let deleted = DocumentFlags(rawValue: 1 << 0)
    
    /// Indicating that the document's access has been removed as a result of
    /// removal from all Sync Gateway channels that a user has access to.
    public static let accessRemoved = DocumentFlags(rawValue: 1 << 1)
    
}

/// Replication Filter.
public typealias ReplicationFilter = (Document, DocumentFlags) -> Bool

/// Replicator configuration.
public struct ReplicatorConfiguration {
    
    /// The local database to replicate with the replication target.
    public let database: Database
    
    /// The replication target to replicate with.
    public let target: Endpoint
    
    /// Replicator type indicating the direction of the replicator.
    public var replicatorType: ReplicatorType = .pushAndPull
    
    /// The continuous flag indicating whether the replicator should stay
    /// active indefinitely to replicate changed documents.
    public var continuous: Bool = false
    
    /// The Authenticator to authenticate with a remote target.
    public var authenticator: Authenticator?
    
    #if COUCHBASE_ENTERPRISE
    /// Specify the replicator to accept any and only self-signed certs. Any non-self-signed certs will be rejected
    /// to avoid accidentally using this mode with the non-self-signed certs in production.
    public var acceptOnlySelfSignedServerCertificate: Bool = false
    #endif
    
    /// The remote target's SSL certificate.
    public var pinnedServerCertificate: SecCertificate?
    
    /// Extra HTTP headers to send in all requests to the remote target.
    public var headers: Dictionary<String, String>?
    
    /// Specific network interface for connecting to the remote target.
    public var networkInterface: String?
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push
    /// replication. If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by
    /// Sync Gateway.
    public var channels: [String]?
    
    /// A set of document IDs to filter by: if given, only documents with
    /// these IDs will be pushed and/or pulled.
    public var documentIDs: [String]?
    
    /**
     Filter closure for validating whether the documents can be pushed to the remote endpoint.
     Only documents for which the closure returns true are replicated.
     */
    public var pushFilter: ReplicationFilter?
    
    /**
     Filter closure for validating whether the documents can be pulled from the remote endpoint.
     Only documents for which the closure returns true are replicated.
     */
    public var pullFilter: ReplicationFilter?
    
    /**
     The custom conflict resolver object can be set here. If this value is not set, or set to nil,
     the default conflict resolver will be applied.
     */
    public var conflictResolver: ConflictResolverProtocol?
    
    #if os(iOS)
    /**
     Allows the replicator to continue replicating in the background. The default
     value is NO, which means that the replicator will suspend itself when the
     replicator detects that the application is running in the background.
     
     If setting the value to YES, please ensure that the application requests
     for extending the background task properly.
     */
    public var allowReplicatingInBackground: Bool = false
    #endif
    
    /**
    The heartbeat interval in second.
    
    The interval when the replicator sends the ping message to check whether the other peer is still alive. Set the value to
    zero(by default) means using the default heartbeat of 300 seconds.
      
    Note: Setting the heartbeat to negative value will result in InvalidArgumentException being thrown.
     */
    public var heartbeat: TimeInterval = 0 {
        willSet(newValue) {
            guard newValue >= 0 else {
                NSException(name: .invalidArgumentException,
                            reason: "Attempt to store negative value in heartbeat",
                            userInfo: nil).raise()
                return
            }
        }
    }
    
    /**
     The maximum attempts to perform retry. The retry attempt will be reset when the replicator is
     able to connect and replicate with the remote server again.
     
     When setting the  _maxAttempts to zero(default), the default maxAttempts of 10 times for single shot
     replicators and infinite times for continuous replicators will be applied and present to users.
     Settings the value to 1, will perform an initial request and if there is a transient error
     occurs, will stop without retry.
     */
    public var maxAttempts: UInt = 0
    
    /**
     Max wait time for the next attempt(retry).
     
     The exponential backoff for calculating the wait time will be used by default and cannot be
     customized. Set the value to zero(by default) means using the default max attempts of
     300 seconds.
     
     Set the maxAttemptWaitTime to negative value will result in InvalidArgumentException
     being thrown.
     */
    public var maxAttemptWaitTime: TimeInterval = 0 {
        willSet(newValue) {
            
            guard newValue >= 0 else {
                NSException(name: .invalidArgumentException,
                            reason: "Attempt to store negative value in maxAttemptWaitTime",
                            userInfo: nil).raise()
                return
            }
        }
    }
    
    /// To enable/disable the auto purge feature
    ///
    /// The default value is true which means that the document will be automatically purged by the
    /// pull replicator when the user loses access to the document from both removed and revoked scenarios.
    ///
    /// When the property is set to false, this behavior is disabled and an access removed event
    /// will be sent to any document listeners that are active on the replicator. For performance
    /// reasons, the document listeners must be added **before** the replicator is started or
    /// they will not receive the events.
    public var enableAutoPurge: Bool = true
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// local database and the replication target.
    ///
    /// - Parameters:
    ///   - database: The local database.
    ///   - target: The replication target.
    public init(database: Database, target: Endpoint) {
        self.database = database
        self.target = target
    }
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// configuration object.
    ///
    /// - Parameter config: The configuration object.
    public init(config: ReplicatorConfiguration) {
        self.database = config.database
        self.target = config.target
        self.replicatorType = config.replicatorType
        self.continuous = config.continuous
        self.authenticator = config.authenticator
        self.pinnedServerCertificate = config.pinnedServerCertificate
        self.headers = config.headers
        self.networkInterface = config.networkInterface
        self.channels = config.channels
        self.documentIDs = config.documentIDs
        self.conflictResolver = config.conflictResolver
        self.heartbeat = config.heartbeat
        self.maxAttempts = config.maxAttempts
        self.maxAttemptWaitTime = config.maxAttemptWaitTime
        self.pullFilter = config.pullFilter
        self.pushFilter = config.pushFilter
        self.enableAutoPurge = config.enableAutoPurge
        
        #if os(iOS)
        self.allowReplicatingInBackground = config.allowReplicatingInBackground
        #endif
        
        #if COUCHBASE_ENTERPRISE
        self.acceptOnlySelfSignedServerCertificate = config.acceptOnlySelfSignedServerCertificate
        #endif
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLReplicatorConfiguration {
        let target = self.target as! IEndpoint
        let c = CBLReplicatorConfiguration(database: self.database._impl, target: target.toImpl())
        c.replicatorType = CBLReplicatorType(rawValue: UInt(self.replicatorType.rawValue))!
        c.continuous = self.continuous
        c.authenticator = (self.authenticator as? IAuthenticator)?.toImpl()
        c.pinnedServerCertificate = self.pinnedServerCertificate
        c.headers = self.headers
        c.networkInterface = self.networkInterface;
        c.channels = self.channels
        c.documentIDs = self.documentIDs
        c.pushFilter = self.filter(push: true)
        c.pullFilter = self.filter(push: false)
        c.heartbeat = self.heartbeat
        c.maxAttempts = self.maxAttempts
        c.maxAttemptWaitTime = self.maxAttemptWaitTime
        c.enableAutoPurge = self.enableAutoPurge
        
        if let resolver = self.conflictResolver {
            c.setConflictResolverUsing { (conflict) -> CBLDocument? in
                return resolver.resolve(conflict: Conflict(impl: conflict))?._impl
            }
        }
        
        #if os(iOS)
        c.allowReplicatingInBackground = self.allowReplicatingInBackground
        #endif
        
        #if COUCHBASE_ENTERPRISE
        c.acceptOnlySelfSignedServerCertificate = self.acceptOnlySelfSignedServerCertificate
        #endif
        return c
    }
    
    func filter(push: Bool) -> CBLReplicationFilter? {
        guard let f = push ? self.pushFilter : self.pullFilter else {
            return nil
        }
        
        return { (doc, flags) in
            return f(Document(doc), DocumentFlags(rawValue: Int(flags.rawValue)))
        }
    }
    
}
