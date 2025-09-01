//
//  CollectionConfiguration.swift
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
import CouchbaseLiteSwift_Private

/// The collection configuration that can be configured specifically for the replication.
public struct CollectionConfiguration {
    /// The collection.
    public var collection: Collection?
    
    /// The custom conflict resolver function. If this value is nil, the default conflict resolver will be used..
    public var conflictResolver: ConflictResolverProtocol?
    
    /// Filter function for validating whether the documents can be pushed to the remote endpoint.
    /// Only documents of which the function returns true are replicated.
    public var pushFilter: ReplicationFilter?
    
    /// Filter function for validating whether the documents can be pulled from the remote endpoint.
    /// Only documents of which the function returns true are replicated.
    public var pullFilter: ReplicationFilter?
    
    /// Channels filter for specifying the channels for the pull the replicator will pull from. For any
    /// collections that do not have the channels filter specified, all accessible channels will be pulled. Push
    /// replicator will ignore this filter.
    ///
    /// - Note:Channels are not supported in Peer-to-Peer and Database-to-Database replication.
    public var channels: Array<String>?
    
    /// Document IDs filter to limit the documents in the collection to be replicated with the remote endpoint.
    /// If not specified, all docs in the collection will be replicated.
    public var documentIDs: Array<String>?
    
    /// Initializes the configuration with the specified collection.
    ///
    /// - Parameter collection: The collection.
    public init(collection: Collection) {
        self.collection = collection
    }
    
    /// Creates an array of `CollectionConfiguration` objects from the given collections.
    ///
    /// Each collection is wrapped in a `CollectionConfiguration`using default settings
    /// (no filters and no custom conflict resolvers).
    ///
    /// This is a convenience method for configuring multiple collections with default configurations.
    ///
    /// - Parameter collections: An array of `Collection` objects to configure for replication.
    /// - Returns: An array of `CollectionConfiguration` objects corresponding to the given collections.
    public static func fromCollections(_ collections: [Collection]) -> [CollectionConfiguration] {
        Precondition.assertNotEmpty(collections, name: "collections")
        return collections.map { CollectionConfiguration(collection: $0) }
    }
    
    /// Creates an array of `CollectionConfiguration` objects from the given collections with the same configuration closure.
    ///
    /// Each collection is wrapped in a `CollectionConfiguration`using default settings
    /// (no filters and no custom conflict resolvers).
    ///
    /// This is a convenience method for configuring multiple collections with the same configuration.
    /// If custom configurations are needed, construct `CollectionConfiguration` objects
    /// directly instead.
    ///
    /// - Parameter collections: An array of `Collection` objects to configure for replication.
    /// - Parameter config: A closure that takes a `CollectionConfiguration` object
    /// - Returns: An array of `CollectionConfiguration` objects corresponding to the given collections.
    /// Creates configurations from an array of collections with a configuration closure.
    static func fromCollections(_ collections: [Collection], config: (CollectionConfiguration) -> Void) -> [CollectionConfiguration] {
        Precondition.assertNotEmpty(collections, name: "collections")
        return collections.map {
            let colConfig = CollectionConfiguration(collection: $0)
            config(colConfig)
            return colConfig
        }
    }
    
    
    
    // MARK: internal
    
    /// Used by ReplicatatorConfiguration's addCollection()
    init(config: CollectionConfiguration?) {
        guard let config = config else { return }
        
        self.collection = config.collection
        self.conflictResolver = config.conflictResolver
        self.pushFilter = config.pushFilter
        self.pullFilter = config.pullFilter
        self.channels = config.channels
        self.documentIDs = config.documentIDs
    }
    
    func toImpl(_ collection: Collection) -> CBLCollectionConfiguration {
        // This function is called by ReplicatorConfiguration's toImpl() to construct
        // the objective-c CBLCollectionConfiguration version.
        //
        // When using the old (deprecated now) api, the collection passed to this function is
        // from the ReplicatorConfiguration used for setting up the filter and
        // conflict resolver wrapper functions. Once we removed the deprecated API,
        // the collection doesn't need to be passed anymore.
        let config = CBLCollectionConfiguration(collection: collection.impl)
        
        config.channels = self.channels
        config.documentIDs = self.documentIDs
        
        if let pushFilter = self.wrapFilter(push: true, collection: collection) {
            config.pushFilter = pushFilter
        }
        
        if let pullFilter = self.wrapFilter(push: false, collection: collection) {
            config.pullFilter = pullFilter
        }
        
        if let resolver = self.conflictResolver {
            config.setConflictResolverUsing { (conflict) -> CBLDocument? in
                return resolver.resolve(conflict: Conflict(impl: conflict, collection: collection))?.impl
            }
        }
        
        return config
    }
    
    func wrapFilter(push: Bool, collection: Collection) -> ((CBLDocument, CBLDocumentFlags) -> Bool)? {
        guard let filter = push ? self.pushFilter : self.pullFilter else {
            return nil
        }
        
        return { (doc, flags) in
            return filter(Document(doc, collection: collection), DocumentFlags(rawValue: Int(flags.rawValue)))
        }
    }
}
 
