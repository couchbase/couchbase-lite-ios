//
//  DocumentReplication.swift
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


/// Document replication event.
public struct DocumentReplication {
    
    /// The source replicator object.
    public let replicator: Replicator
    
    /// The flag indicating that the replication is push or pull.
    public let isPush: Bool
    
    /// The document ID.
    public let documentID: String
    
    /// The error if occurred.
    public let error: Error?
    
}

