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
public final class ReplicatorConfiguration {
    
    /// The local database to replicate with the replication target.
    public let database: Database
    
    /// The replication target to replicate with.
    public let target: Endpoint
    
    /// Replicator type indicating the direction of the replicator.
    public let replicatorType: ReplicatorType
    
    /// The continuous flag indicating whether the replicator should stay
    /// active indefinitely to replicate changed documents.
    public let continuous: Bool
    
    /// The conflict resolver for this replicator.
    public let conflictResolver: ConflictResolver
    
    /// The Authenticator to authenticate with a remote target.
    public let authenticator: Authenticator?
    
    /// The remote target's SSL certificate.
    public let pinnedServerCertificate: SecCertificate?
    
    /// Extra HTTP headers to send in all requests to the remote target.
    public let headers: Dictionary<String, String>?
    
    /// A set of Sync Gateway channel names to pull from. Ignored for push
    /// replication. If unset, all accessible channels will be pulled.
    /// Note: channels that are not accessible to the user will be ignored by
    /// Sync Gateway.
    public let channels: [String]?
    
    /// A set of document IDs to filter by: if given, only documents with
    /// these IDs will be pushed and/or pulled.
    public let documentIDs: [String]?
    
    
    /// The builder for the ReplicatorConfiguration.
    public class Builder {
        /// Initializes a ReplicatorConfiguration's builder with the given
        /// local database and the replication target.
        ///
        /// - Parameters:
        ///   - database: The local database.
        ///   - target: The replication target.
        public init(withDatabase database: Database, target: Endpoint) {
            self.database = database
            self.target = target
            self.replicatorType = .pushAndPull
            self.continuous = false
        }
        
        
        /// Initializes a ReplicatorConfiguration's builder with the given
        /// configuration object.
        ///
        /// - Parameter config: The configuration object.
        public init(withConfig config: ReplicatorConfiguration) {
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
        }
            
        
        /// Sets the replicator type indicating the direction of the replicator.
        /// The default value is .pushAndPull which is bidrectional.
        ///
        /// - Parameter replicatorType: The replicator type.
        /// - Returns: The self object.
        @discardableResult public func setReplicatorType(_ replicatorType: ReplicatorType) -> Self {
            self.replicatorType = replicatorType
            return self
        }
        
        
        /// Sets whether the replicator stays active indefinitely to replicate
        /// changed documents. The default value is false, which means that the
        /// replicator will stop after it finishes replicating the changed
        /// documents.
        ///
        /// - Parameter continuous: The continuous flag.
        /// - Returns: The self object.
        @discardableResult public func setContinuous(_ continuous: Bool) -> Self {
            self.continuous = continuous
            return self
        }
        
        
        /// Sets the custom conflict resolver for this replicator. Without
        /// setting the conflict resolver, CouchbaseLite will use the default
        /// conflict resolver.
        ///
        /// - Parameter conflictResolver: The conflict resolver.
        /// - Returns: The self object.
        @discardableResult public func setConflictResolver(_ conflictResolver: ConflictResolver) -> Self {
            self.conflictResolver = conflictResolver
            return self
        }
        
        
        /// Sets the authenticator to authenticate with a remote target server.
        /// Currently there are two types of the authenticators,
        /// BasicAuthenticator and SessionAuthenticator, supported.
        ///
        /// - Parameter authenticator: The authenticator.
        /// - Returns: The self object.
        @discardableResult public func setAuthenticator(_ authenticator: Authenticator?) -> Self {
            self.authenticator = authenticator
            return self
        }
        
        
        /// Sets the target server's SSL certificate.
        ///
        /// - Parameter pinnedServerCertificate: the SSL certificate.
        /// - Returns: The self object.
        @discardableResult public func setPinnedServerCertificate(_ pinnedServerCertificate: SecCertificate?) -> Self {
            self.pinnedServerCertificate = pinnedServerCertificate
            return self
        }
        
        
        /// Sets the extra HTTP headers to send in all requests to the remote target.
        ///
        /// - Parameter headers: The HTTP Headers.
        /// - Returns: The self object.
        @discardableResult public func setHeaders(_ headers: Dictionary<String, String>?) -> Self {
            self.headers = headers
            return self
        }
        
        
        /// Sets a set of Sync Gateway channel names to pull from. Ignored for
        /// push replication. If unset, all accessible channels will be pulled.
        /// Note: channels that are not accessible to the user will be ignored
        /// by Sync Gateway.
        ///
        /// - Parameter channels: The Sync Gateway channel names.
        /// - Returns: The self object.
        @discardableResult public func setChannels(_ channels: [String]?) -> Self {
            self.channels = channels
            return self
        }
        
        
        /// Sets a set of document IDs to filter by: if given, only documents
        /// with these IDs will be pushed and/or pulled.
        ///
        /// - Parameter documentIDs: The document IDs.
        /// - Returns: The self object.
        @discardableResult public func setDocumentIDs(_ documentIDs: [String]?) -> Self {
            self.documentIDs = documentIDs
            return self
        }
        
        
        /// Build a ReplicatorConfiguration object with the current settings.
        ///
        /// - Returns: The ReplicatorConfiguration object.
        public func build() -> ReplicatorConfiguration {
            return ReplicatorConfiguration(withBuilder: self)
        }
        
        
        // MARK: Internal
        
        
        let database: Database
        
        let target: Endpoint
        
        var replicatorType: ReplicatorType
        
        var continuous: Bool
        
        var conflictResolver: ConflictResolver = DefaultConflictResolver()
        
        var authenticator: Authenticator?
        
        var pinnedServerCertificate: SecCertificate?
        
        var headers: Dictionary<String, String>?
        
        var channels: [String]?
        
        var documentIDs: [String]?
    }
    
    
    // MARK: Internal
    
    
    init(withBuilder builder: Builder) {
        self.database = builder.database
        self.target = builder.target
        self.replicatorType = builder.replicatorType
        self.continuous = builder.continuous
        self.conflictResolver = builder.conflictResolver
        self.authenticator = builder.authenticator
        self.pinnedServerCertificate = builder.pinnedServerCertificate
        self.headers = builder.headers
        self.channels = builder.channels
        self.documentIDs = builder.documentIDs
    }
    
    
    func toImpl() -> CBLReplicatorConfiguration {
        let t = self.target as! InternalEndpoint
        let c = CBLReplicatorConfiguration(
        database: self.database._impl, target: t.toImpl()) { (builder) in
            builder.replicatorType = CBLReplicatorType(rawValue:
                UInt32(self.replicatorType.rawValue))
            
            if !(self.conflictResolver is DefaultConflictResolver) {
                builder.conflictResolver =
                    BridgingConflictResolver(resolver: self.conflictResolver)
            }
            
            builder.continuous = self.continuous
            builder.authenticator = self.authenticator
            builder.pinnedServerCertificate = self.pinnedServerCertificate
            builder.headers = self.headers
            builder.channels = self.channels
            builder.documentIDs = self.documentIDs
        }
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
