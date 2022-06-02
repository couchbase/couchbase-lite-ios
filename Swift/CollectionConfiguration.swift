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

public struct CollectionConfiguration {
    /// The custom conflict resolver function. If this value is nil, the default conflict resolver will be used..
    public var conflictResolver: ConflictResolver?
    
    /// Filter function for validating whether the documents can be pushed to the remote endpoint.
    /// Only documents of which the function returns true are replicated.
    public var pushFilter: ReplicationFilter?
    
    /// Filter function for validating whether the documents can be pulled from the remote endpoint.
    /// Only documents of which the function returns true are replicated.
    public var pullFilter: ReplicationFilter?
    
    /// Channels filter for specifying the channels for the pull the replicator will pull from. For any
    /// collections that do not have the channels filter specified, all accessible channels will be pulled. Push
    /// replicator will ignore this filter.
    public var channels: Array<String>?
    
    /// Document IDs filter to limit the documents in the collection to be replicated with the remote endpoint.
    /// If not specified, all docs in the collection will be replicated.
    public var documentIDs: Array<String>?
}
 
