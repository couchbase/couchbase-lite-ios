//
//  Conflict.swift
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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

/// Conflict class
public struct Conflict {
    
    /// The document which is already in the database.
    public var localDocument: Document? {
        guard let doc = impl.localDocument else {
            return nil
        }
        return Document(doc)
    }
    
    /// The document which is merging to the database.
    public var remoteDocument: Document? {
        guard let doc = impl.remoteDocument else {
            return nil
        }
        return Document(doc)
    }
    
    // MARK: Internal
    let impl: CBLConflict
}
