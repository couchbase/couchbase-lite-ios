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
    
    /// The local database to replicate with the target database.
    public let database: Database
    
    /// The replication target to replicate with. The replication target can be either a URL to
    /// the remote database or a local databaes.
    public let target: Any
    
    /// Replication type indicating the direction of the replication. The default value is
    /// .pushAndPull which is bidrectional.
    public var replicatorType: ReplicatorType
    
    /// Should the replicator stay active indefinitely, and push/pull changed documents?. The
    /// default value is false.
    public var continuous: Bool
    
    /// The conflict resolver for this replicator. The default value is nil, which means the default
    /// algorithm will be used, where the revision with more history wins.
    public var conflictResolver: ConflictResolver?
    
    /// An Authenticator to authenticate with a remote server. Currently there are two types of
    /// the authenticators, BasicAuthenticator and SessionAuthenticator, supported.
    public var authenticator: Authenticator?
    
    /// If this property is non-null, the server is required to have this exact SSL/TLS certificate,
    /// or the connection will fail.
    public var pinnedServerCertificate: SecCertificate?
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push replication.
    /// If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by Sync Gateway.
    public var channels: [String]?
    
    /// A set of document IDs to filter by: if given, only documents with these IDs will be pushed
    /// and/or pulled.
    public var documentIDs: [String]?
    
    /// Initialize a ReplicatorConfiguration with the given local database and remote database URL.
    ///
    /// - Parameters:
    ///   - database: The local database.
    ///   - targetURL: the target URL.
    public init(database: Database, targetURL: URL) {
        self.database = database
        self.target = targetURL
        self.replicatorType = .pushAndPull
        self.continuous = false
    }
    
    
    /// Initialize a ReplicatorConfiguration with the given local database and another local database.
    ///
    /// - Parameters:
    ///   - database: The local database.
    ///   - targetDatabase: The target database.
    public init(database: Database, targetDatabase: Database) {
        self.database = database
        self.target = targetDatabase
        self.replicatorType = .pushAndPull
        self.continuous = false
    }
}

/// The Authenticator.
public typealias Authenticator = CBLAuthenticator

/// The BasicAuthenticator.
public typealias BasicAuthenticator = CBLBasicAuthenticator

/// The ClientCertAuthenticator.
public typealias ClientCertAuthenticator = CBLClientCertAuthenticator

/// The SessionAuthenticator.
public typealias SessionAuthenticator = CBLSessionAuthenticator
