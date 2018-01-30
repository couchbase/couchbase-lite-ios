//
//  ReplicatorConfiguration.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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


/// Replicator configuration.
public struct ReplicatorConfiguration {
    
    /// The local database to replicate with the replication target.
    public let database: Database
    
    /// The replication target to replicate with.
    public let target: Endpoint
    
    /// Replicator type indicating the direction of the replicator.
    public var replicatorType: ReplicatorType = .pushAndPull {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The continuous flag indicating whether the replicator should stay
    /// active indefinitely to replicate changed documents.
    public var continuous: Bool = false {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The conflict resolver for this replicator.
    public var conflictResolver: ConflictResolver = DefaultConflictResolver() {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The Authenticator to authenticate with a remote target.
    public var authenticator: Authenticator? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The remote target's SSL certificate.
    public var pinnedServerCertificate: SecCertificate? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// Extra HTTP headers to send in all requests to the remote target.
    public var headers: Dictionary<String, String>? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push
    /// replication. If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by
    /// Sync Gateway.
    public var channels: [String]? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// A set of document IDs to filter by: if given, only documents with
    /// these IDs will be pushed and/or pulled.
    public var documentIDs: [String]? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// local database and the replication target.
    ///
    /// - Parameters:
    ///   - database: The local database.
    ///   - target: The replication target.
    public init(withDatabase database: Database, target: Endpoint) {
        self.database = database
        self.target = target
        self.readonly = false
    }
    
    /// Initializes a ReplicatorConfiguration's builder with the given
    /// configuration object.
    ///
    /// - Parameter config: The configuration object.
    public init(withConfig config: ReplicatorConfiguration) {
        self.init(withConfig: config, readonly: false)
    }
    
    // MARK: Internal
    
    private let readonly: Bool
    
    init(withConfig config: ReplicatorConfiguration, readonly: Bool) {
        self.database = config.database
        self.target = config.target
        self.replicatorType = config.replicatorType
        self.continuous = config.continuous
        self.conflictResolver = config.conflictResolver
        self.authenticator = config.authenticator
        self.pinnedServerCertificate = config.pinnedServerCertificate
        self.headers = config.headers
        self.channels = config.channels
        self.documentIDs = config.documentIDs
        self.readonly = readonly
    }
    
    func checkReadOnly() {
        if self.readonly {
            fatalError("This configuration object is readonly.")
        }
    }
    
    func toImpl() -> CBLReplicatorConfiguration {
        let t = self.target as! InternalEndpoint
        let c = CBLReplicatorConfiguration(database: self.database._impl, target: t.toImpl())
        c.replicatorType = CBLReplicatorType(rawValue:
            UInt32(self.replicatorType.rawValue))
        if !(self.conflictResolver is DefaultConflictResolver) {
            c.conflictResolver =
                BridgingConflictResolver(resolver: self.conflictResolver)
        }
        c.continuous = self.continuous
        c.authenticator = self.authenticator
        c.pinnedServerCertificate = self.pinnedServerCertificate
        c.headers = self.headers
        c.channels = self.channels
        c.documentIDs = self.documentIDs
        return c
    }
}


// MARK: Type aliases

/// The Authenticator.
public typealias Authenticator = CBLAuthenticator

/// The BasicAuthenticator.
public typealias BasicAuthenticator = CBLBasicAuthenticator

/// The SessionAuthenticator.
public typealias SessionAuthenticator = CBLSessionAuthenticator
