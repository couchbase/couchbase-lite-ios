//
//  Indexable.swift
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

/// The Indexable interface defines a set of functions for managing the query indexes.
public protocol Indexable {
    /// Return all index names, or nil if an error occurred.
    func indexes() throws -> [String]
    
    /// Create an index with the index name and config.
    func createIndex(withName name: String, config: IndexConfiguration) throws
    
    /// Create an index with the index and index name. 
    func createIndex(_ index: Index, name: String) throws;
    
    /// Delete an index by name.
    func deleteIndex(forName name: String) throws
    
    /// Return an index object, or nil if the index doesn't exist.
    func index(withName name: String) throws -> QueryIndex?
}
