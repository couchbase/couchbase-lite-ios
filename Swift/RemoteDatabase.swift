//
//  RemoteDatabase.swift
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

/// This is a wrapper for Sync Gateway's CRUD APIs.
/// https://docs.couchbase.com/sync-gateway/current/rest-api.html
public class RemoteDatabase {
    /// Creates a new RemoteDatabase instance, and starts it automatically.
    public init(url: URL, authenticator: Authenticator? = nil) {
        impl = CBLRemoteDatabase(url: url, authenticator: (authenticator as? IAuthenticator)?.toImpl())
    }
    
    /// Gets an existing document with the given ID. If a document with the given ID
    /// doesn't exist in the database, the value returned will be nil.
    public func document(withID id: String, completion: @escaping (_ document: Document?) -> Void) {
        self.impl.document(withID: id) { (doc: CBLDocument?, error: Error?) in
            if let cblDoc = doc {
                completion(Document(cblDoc))
            } else {
                completion(nil)
            }
        }
    }
    
    /// Stop and close the connection with the remote database.
    public func stop() {
        self.impl.stop()
    }
    
    /// Saves a document to the remote database.
    public func saveDocument(document: MutableDocument, completion: @escaping (_ document: Document?) -> Void) {
        guard let mDoc = (document._impl as? CBLMutableDocument) else {
            fatalError("document is not MutableDocument type!")
        }
        
        self.impl.save(mDoc) { (doc: CBLDocument?, error: Error?) in
            if let cblDoc = doc {
                completion(Document(cblDoc))
            } else {
                completion(nil)
            }
        }
    }
    
    /// Deletes a document from the remote database.
    public func deleteDocument(document: Document, completion: @escaping (_ document: Document?) -> Void) {
        self.impl.delete(document._impl) { (doc: CBLDocument?, error: Error?) in
            if let cblDoc = doc {
                completion(Document(cblDoc))
            } else {
                completion(nil)
            }
        }
    }
    
    // MARK: Internal
    
    let impl: CBLRemoteDatabase
}
