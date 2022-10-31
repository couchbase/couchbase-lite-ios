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
    @available(*, deprecated, message: "Use config.collections instead.")
    public var database: Database {
        guard let db = self.db else {
            fatalError("Attempt to access database property but no collections added")
        }
        return db
    }
    
    /// The replication target to replicate with.
    public let target: Endpoint
    
    /// Replicator type indicating the direction of the replicator.
    public var replicatorType: ReplicatorType = ReplicatorConfiguration.defaultType
    
    /// The continuous flag indicating whether the replicator should stay
    /// active indefinitely to replicate changed documents.
    public var continuous: Bool = ReplicatorConfiguration.defaultContinuous {
        willSet(newValue) {
            if !didMaxAttemptUpdate {
                maxAttempts = newValue
                ? ReplicatorConfiguration.defaultMaxAttemptsContinuous
                : ReplicatorConfiguration.defaultMaxAttemptsSingleShot
            }
        }
    }
    
    /// The Authenticator to authenticate with a remote target.
    public var authenticator: Authenticator?
    
    #if COUCHBASE_ENTERPRISE
    /// Specify the replicator to accept any and only self-signed certs. Any non-self-signed certs will be rejected
    /// to avoid accidentally using this mode with the non-self-signed certs in production.
    public var acceptOnlySelfSignedServerCertificate: Bool = false
    #endif
    
    /// The remote target's SSL certificate.
    ///
    /// - Note: The pinned cert will be evaluated against any certs in a cert chain,
    /// and the cert chain will be valid only if the cert chain contains the pinned cert.
    public var pinnedServerCertificate: SecCertificate?
    
    /// Extra HTTP headers to send in all requests to the remote target.
    public var headers: Dictionary<String, String>?
    
    /// Specific network interface for connecting to the remote target.
    public var networkInterface: String?
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push
    /// replication. If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by
    /// Sync Gateway.
    @available(*, deprecated, message: """
                Use init(target:) and config.addCollection(config:) with a CollectionConfiguration
                object instead
                """)
    public var channels: [String]? {
        set {
            var colConfig = defaultCollectionConfigOrNever
            colConfig.channels = newValue
            setDefaultCollectionConfig(colConfig)
        }
        
        get { defaultCollectionConfig?.channels }
    }
    
    /// A set of document IDs to filter by: if given, only documents with
    /// these IDs will be pushed and/or pulled.
    @available(*, deprecated, message: """
                Use init(target:) and config.addCollection(config:) with a CollectionConfiguration
                object instead
                """)
    public var documentIDs: [String]? {
        set {
            var colConfig = defaultCollectionConfigOrNever
            colConfig.documentIDs = newValue
            setDefaultCollectionConfig(colConfig)
        }
        
        get { defaultCollectionConfig?.documentIDs }
    }
    
    
    /// Filter closure for validating whether the documents can be pushed to the remote endpoint.
    /// Only documents for which the closure returns true are replicated.
    @available(*, deprecated, message: """
                Use init(target:) and config.addCollection(config:) with a CollectionConfiguration
                object instead
                """)
    public var pushFilter: ReplicationFilter? {
        set {
            var colConfig = defaultCollectionConfigOrNever
            colConfig.pushFilter = newValue
            setDefaultCollectionConfig(colConfig)
        }
        
        get { defaultCollectionConfig?.pushFilter }
    }
    
    /// Filter closure for validating whether the documents can be pulled from the remote endpoint.
    /// Only documents for which the closure returns true are replicated.
    @available(*, deprecated, message: """
                Use init(target:) and config.addCollection(config:) with a CollectionConfiguration
                object instead
                """)
    public var pullFilter: ReplicationFilter? {
        set {
            var colConfig = defaultCollectionConfigOrNever
            colConfig.pullFilter = newValue
            setDefaultCollectionConfig(colConfig)
        }
        
        get { defaultCollectionConfig?.pullFilter }
    }
    
    /// The custom conflict resolver object can be set here. If this value is not set, or set to nil,
    /// the default conflict resolver will be applied.
    @available(*, deprecated, message: """
                Use init(target:) and config.addCollection(config:) with a CollectionConfiguration
                object instead
                """)
    public var conflictResolver: ConflictResolverProtocol? {
        set {
            var colConfig = defaultCollectionConfigOrNever
            colConfig.conflictResolver = newValue
            setDefaultCollectionConfig(colConfig)
        }
        
        get { defaultCollectionConfig?.conflictResolver }
    }
    
    #if os(iOS)
    /// Allows the replicator to continue replicating in the background. The default
    /// value is NO, which means that the replicator will suspend itself when the
    /// replicator detects that the application is running in the background.
    ///
    /// If setting the value to YES, please ensure that the application requests
    /// for extending the background task properly.
    public var allowReplicatingInBackground: Bool = ReplicatorConfiguration.defaultAllowReplicatingInBackground
    #endif
    
    /// The heartbeat interval in second.
    ///
    /// The interval when the replicator sends the ping message to check whether the other peer is
    /// still alive. Default heartbeat is ``ReplicatorConfiguration.defaultHeartbeat`` secs.
    ///
    /// - Note: Setting the heartbeat to negative value will result in InvalidArgumentException
    ///         being thrown. For backward compatibility, setting it to zero will result in
    ///         default 300 secs internally.
    public var heartbeat: TimeInterval = ReplicatorConfiguration.defaultHeartbeat {
        willSet(newValue) {
            guard newValue >= 0 else {
                NSException(name: .invalidArgumentException,
                            reason: "Attempt to store negative value in heartbeat",
                            userInfo: nil).raise()
                return
            }
        }
    }
    
    /// The maximum attempts to perform retry. The retry attempt will be reset when the replicator is
    /// able to connect and replicate with the remote server again.
    ///
    /// Default _maxAttempts_ is ``ReplicatorConfiguration.defaultMaxAttemptsSingleShot`` times
    /// for single shot replicators and ``ReplicatorConfiguration.defaultMaxAttemptsContinuous`` times
    /// for continuous replicators.
    ///
    /// Settings the value to 1, will perform an initial request and if there is a transient error
    /// occurs, will stop without retry.
    ///
    /// - Note: For backward compatibility, setting it to zero will result in default 10 internally.
    public var maxAttempts: UInt = UInt(ReplicatorConfiguration.defaultMaxAttemptsSingleShot) {
        didSet { didMaxAttemptUpdate = true }
    }
    
    /// Max wait time for the next attempt(retry).
    ///
    /// The exponential backoff for calculating the wait time will be used by default and cannot be
    /// customized. Default max attempts is ``ReplicatorConfiguration.defaultMaxAttemptWaitTime`` secs.
    ///
    /// Set the maxAttemptWaitTime to negative value will result in InvalidArgumentException
    /// being thrown.
    ///
    /// - Note: For backward compatibility, setting it to zero will result in default secs internally.
    public var maxAttemptWaitTime: TimeInterval = ReplicatorConfiguration.defaultMaxAttemptWaitTime {
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
    public var enableAutoPurge: Bool = ReplicatorConfiguration.defaultEnableAutoPurge
    
    /// The collections used for the replication.
    public var collections: [Collection] {
        return Array(self.collectionConfigs.keys)
    }
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// local database and the replication target.
    ///
    /// - Parameters:
    ///   - database: The local database.
    ///   - target: The replication target.
    @available(*, deprecated, message: " Use init(target:) instead. ")
    public init(database: Database, target: Endpoint) {
        self.db = database
        self.target = target
        
        initCollectionConfigs()
    }
    
    /// Create a ReplicatorConfiguration object with the target’s endpoint. After the ReplicatorConfiguration
    /// object is created, use addCollection(_ collection:, config:) or addCollections(_ collections:, config:) to
    /// specify and configure the collections used for replicating with the target. If there are no collections
    /// specified, the replicator will fail to start with a no collections specified error.
    public init(target: Endpoint) {
        self.target = target
        
        initCollectionConfigs()
    }
    
    /// Add a collection used for the replication with an optional collection configuration. If the collection has
    /// been added before, the previous added and its configuration if specified will be replaced. If a nil
    /// configuration is specified, a default empty configuration will be applied.
    @discardableResult
    public mutating func addCollection(_ collection: Collection,
                              config: CollectionConfiguration? = nil) -> ReplicatorConfiguration {
        
        if !collection.impl.isValid {
            fatalError("Attempt to add an invalid collection.")
        }
        
        let db = collection.db
        if let db1 = self.db {
            if db1.impl != db.impl {
                fatalError("Attempt to add collection from different databases.")
            }
        } else {
            self.db = db
        }
        
        var colConfig: CollectionConfiguration!
        if let config = config {
            colConfig = CollectionConfiguration(config: config)
        } else {
            colConfig = CollectionConfiguration()
        }
        
        self.collectionConfigs[collection] = colConfig
        
        return self
    }
    
    /// Add multiple collections used for the replication with an optional shared collection configuration.
    /// If any of the collections have been added before, the previously added collections and their
    /// configuration if specified will be replaced. Adding an empty collection array will be no-ops. if
    /// specified will be replaced. If a nil configuration is specified, a default empty configuration will be
    /// applied.
    @discardableResult
    public mutating func addCollections(_ collections: Array<Collection>,
                                        config: CollectionConfiguration? = nil) -> ReplicatorConfiguration {
        
        if collections.count == 0 {
            fatalError("Attempt to add empty collection array.")
        }
        
        for col in collections {
            addCollection(col, config: config)
        }
        
        return self
    }
    
    /// Remove the collection. If the collection doesn’t exist, this operation will be no ops.
    @discardableResult
    public mutating func removeCollection(_ collection: Collection) -> ReplicatorConfiguration {
        self.collectionConfigs.removeValue(forKey: collection)
        
        if self.collectionConfigs.isEmpty {
            self.db = nil
        }
        
        return self
    }
    
    /// Get a copy of the collection’s config. If the config needs to be changed for the collection, the
    /// collection will need to be re-added with the updated config.
    ///
    /// - Parameter collection The collection whose config is needed.
    /// - Returns The collection config if exists.
    public func collectionConfig(_ collection: Collection) -> CollectionConfiguration? {
        return self.collectionConfigs[collection]
    }
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// configuration object.
    ///
    /// - Parameter config: The configuration object.
    public init(config: ReplicatorConfiguration) {
        self.db = config.database
        self.target = config.target
        self.replicatorType = config.replicatorType
        self.continuous = config.continuous
        self.authenticator = config.authenticator
        self.pinnedServerCertificate = config.pinnedServerCertificate
        self.headers = config.headers
        self.networkInterface = config.networkInterface
        self.heartbeat = config.heartbeat
        self.maxAttempts = config.maxAttempts
        self.maxAttemptWaitTime = config.maxAttemptWaitTime
        self.enableAutoPurge = config.enableAutoPurge
        
        for (col, config) in config.collectionConfigs {
            if !col.isValid {
                fatalError("Tries to add invalid collection")
            }
            
            self.collectionConfigs[col] = config
        }
        
        #if os(iOS)
        self.allowReplicatingInBackground = config.allowReplicatingInBackground
        #endif
        
        #if COUCHBASE_ENTERPRISE
        self.acceptOnlySelfSignedServerCertificate = config.acceptOnlySelfSignedServerCertificate
        #endif
    }
    
    // MARK: Internal
    
    var defaultCollectionConfig: CollectionConfiguration? {
        guard let col = try? self.database.defaultCollection() else {
            fatalError("Default collection is missing!")
        }
        
        if let config = self.collectionConfigs[col] {
            return config
        }
        
        return nil
    }
    
    var defaultCollectionConfigOrNever: CollectionConfiguration {
        guard let colConfig = defaultCollectionConfig else {
            fatalError("No default collection added to the configuration")
        }
        
        return colConfig
    }
    
    mutating func setDefaultCollectionConfig(_ config: CollectionConfiguration) {
        guard let col = try? self.database.defaultCollection() else {
            fatalError("Default collection is missing!")
        }
        
        self.collectionConfigs[col] = config
    }
    
    func toImpl() -> CBLReplicatorConfiguration {
        let target = self.target as! IEndpoint
        var c = CBLReplicatorConfiguration(target: target.toImpl())
        c.replicatorType = CBLReplicatorType(rawValue: UInt(self.replicatorType.rawValue))!
        c.continuous = self.continuous
        c.authenticator = (self.authenticator as? IAuthenticator)?.toImpl()
        c.pinnedServerCertificate = self.pinnedServerCertificate
        c.headers = self.headers
        c.networkInterface = self.networkInterface;
        c.heartbeat = self.heartbeat
        c.maxAttempts = self.maxAttempts
        c.maxAttemptWaitTime = self.maxAttemptWaitTime
        c.enableAutoPurge = self.enableAutoPurge
        
        for (col, config) in self.collectionConfigs {
            if !col.isValid {
                fatalError("Attempt to add an invalid collection")
            }
            
            c.addCollection(col.impl, config: config.toImpl(col))
        }
        
        if let resolver = self.conflictResolver {
            c.setConflictResolverUsing { (conflict) -> CBLDocument? in
                guard let col = try? self.database.defaultCollection() else {
                    Database.throwNotOpenError()
                }
                
                return resolver.resolve(conflict: Conflict(impl: conflict, collection: col))?.impl
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
            guard let col = try? self.database.defaultCollection() else {
                Database.throwNotOpenError()
            }
            
            return f(Document(doc, collection: col), DocumentFlags(rawValue: Int(flags.rawValue)))
        }
    }
    
    mutating func initCollectionConfigs() {
        if let db = self.db {
            guard let col = try? db.defaultCollection() else {
                Database.throwNotOpenError()
            }
            
            let colConfig = CollectionConfiguration()
            addCollection(col, config: colConfig)
        }
    }
    
    var collectionConfigs = [Collection: CollectionConfiguration]()
    
    var db: Database?
    
    fileprivate var didMaxAttemptUpdate: Bool = false
}
