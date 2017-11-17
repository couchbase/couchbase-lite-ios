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
    
    
    /// Extra HTTP headers to send in all requests to the remote target.
    public var headers: Dictionary<String, String>?
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push replication.
    /// If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by Sync Gateway.
    public var channels: [String]?
    
    /// A set of document IDs to filter by: if given, only documents with these IDs will be pushed
    /// and/or pulled.
    public var documentIDs: [String]?
    
    #if os(iOS)
    /// Allows the replicator to run when the app goes into the background.
    /// The default value is NO which means that the replicator will suspend itself when the app
    /// goes into the background, and will automatically resume when the app is brought into
    /// the foreground. The replicator will also resume when the -start method is called; this
    /// allows the replicator to be started or run when the app is already in the background.
    /// The replicator will suspend itself or stop (for a non-continuous replicator) when the
    /// replicator is inactive or the background task is expired.
    ///
    /// If the runInBackground property is set to YES, the replicator
    /// will allow to continue running in the background without suspension; it is the
    /// app's responsibility to manage the replicator running status when the app enters into the
    /// background, and comes back to the foreground.
    public var runInBackground: Bool
    #endif
    ///
    
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
        
        #if os(iOS)
        self.runInBackground = false
        #endif
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
        
        #if os(iOS)
        self.runInBackground = false
        #endif
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
