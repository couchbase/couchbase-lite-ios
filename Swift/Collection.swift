//
//  Collection.swift
//  CouchbaseLite
//
//  Copyright (c) 2024-present Couchbase, Inc All rights reserved.
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

/// A `Collection` represent a collection which is a container for documents.
///
/// A collection can be thought as a table in the relational database. Each collection belongs to
/// a scope which is simply a namespce, and has a name which is unique within its scope.
///
/// When a new database is created, a default collection named `_default` will be automatically
/// created. The default collection is created under the default scope named `_default`.
/// The name of the default collection and scope can be referenced by using
/// `Collection.defaultCollectionName` and `Scope.defaultScopeName` constant.
///
/// - Note: The default collection cannot be deleted.
///
/// When creating a new collection, the collection name, and the scope name are required.
/// The naming rules of the collections and scopes are as follows:
/// - Must be between 1 and 251 characters in length.
/// - Can only contain the characters A-Z, a-z, 0-9, and the symbols _, -, and %.
/// - Cannot start with _ or %.
/// - Both scope and collection names are case sensitive.
///
/// ## Collection Lifespan
/// A `Collection` object and its reference remain valid until either
/// the database is closed or the collection itself is deleted, in that case it will
/// throw an NSError with the CBLError.notOpen code while accessing the collection APIs.
///
/// ## Legacy Database and API
/// When using the legacy database, the existing documents and indexes in the database will be
/// automatically migrated to the default collection.
///
/// Any pre-existing database functions that refer to documents, listeners, and indexes without
/// specifying a collection such as `database.document(id:)` will implicitly operate on
/// the default collection. In other words, they behave exactly the way they used to, but
/// collection-aware code should avoid them and use the new Collection API instead.
/// These legacy functions are deprecated and will be removed eventually.
///
public final class Collection : CollectionChangeObservable, Indexable, Equatable, Hashable {
    
    /// The default scope name constant
    public static let defaultCollectionName: String = kCBLDefaultCollectionName
    
    /// Collection's name.
    public var name: String { impl.name }
    
    /// Collection's fully qualified name in the '<scope-name>.<collection-name>' format.
    public var fullName: String { impl.fullName }
    
    /// Collection's scope.
    public let scope: Scope
    
    /// Collection's database
    public let database: Database
    
    // MARK: Document Management
    
    /// Total number of documents in the collection.
    public var count: UInt64 { impl.count }
    
    /// Get an existing document by document ID.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func document(id: String) throws -> Document? {
        var error: NSError?
        let doc = impl.document(withID: id, error: &error)
        if let err = error {
            throw err
        }
        if let implDoc = doc {
            return Document(implDoc, collection: self)
        }
        return nil
    }
    
    /// Gets document fragment object by the given document ID.
    public subscript(key: String) -> DocumentFragment {
        return DocumentFragment(impl[key], collection: self)
    }
    
    /// Save a document into the collection. The default concurrency control, lastWriteWins,
    /// will be used when there is conflict during  save.
    ///
    /// When saving a document that already belongs to a collection, the collection instance of
    /// the document and this collection instance must be the same, otherwise, the InvalidParameter
    /// error will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func save(document: MutableDocument) throws {
        try impl.save(document.impl as! CBLMutableDocument)
    }
    
    /// Save a document into the collection with a specified concurrency control. When specifying
    /// the failOnConflict concurrency control, and conflict occurred, the save operation will fail with
    /// 'false' value returned.
    ///
    /// When saving a document that already belongs to a collection, the collection instance of the
    /// document and this collection instance must be the same, otherwise, the InvalidParameter
    /// error will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func save(document: MutableDocument, concurrencyControl: ConcurrencyControl) throws -> Bool {
        var error: NSError?
        let cc = concurrencyControl == .lastWriteWins ?
            CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict
        let result = impl.save(document.impl as! CBLMutableDocument, concurrencyControl: cc, error: &error)
        if let err = error {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
        return result
    }
    
    /// Save a document into the collection with a specified conflict handler. The specified conflict handler
    /// will be called if there is conflict during save. If the conflict handler returns 'false', the save operation
    /// will be canceled with 'false' value returned.
    ///
    /// When saving a document that already belongs to a collection, the collection instance of the
    /// document and this collection instance must be the same, otherwise, the InvalidParameter error
    /// will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func save(document: MutableDocument,
              conflictHandler: @escaping (MutableDocument, Document?) -> Bool) throws -> Bool {
        
        var error: NSError?
        let result = impl.save(
            document.impl as! CBLMutableDocument,
            conflictHandler: { (cur: CBLMutableDocument, old: CBLDocument?) -> Bool in
                return conflictHandler(document, old != nil ? Document(old!, collection: self) : nil)
            }, error: &error)
        if let err = error {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
        return result
    }
    
    /// Delete a document from the collection. The default concurrency control, lastWriteWins, will be used
    /// when there is conflict during delete. If the document doesn't exist in the collection, the NotFound
    /// error will be thrown.
    ///
    /// When deleting a document that already belongs to a collection, the collection instance of
    /// the document and this collection instance must be the same, otherwise, the InvalidParameter error
    /// will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func delete(document: Document) throws {
        try impl.delete(document.impl)
    }
    
    /// Delete a document from the collection with a specified concurrency control. When specifying
    /// the failOnConflict concurrency control, and conflict occurred, the delete operation will fail with
    /// 'false' value returned.
    ///
    /// When deleting a document, the collection instance of the document and this collection instance
    /// must be the same, otherwise, the InvalidParameter error will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func delete(document: Document, concurrencyControl: ConcurrencyControl) throws -> Bool {
        let cc = concurrencyControl == .lastWriteWins ?
            CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict
        
        var error: NSError?
        let result = impl.delete(document.impl, concurrencyControl: cc, error: &error)
        if let err = error {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
        return result
    }
    
    /// When purging a document, the collection instance of the document and this collection instance
    /// must be the same, otherwise, the InvalidParameter error will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func purge(document: Document) throws {
        try impl.purgeDocument(document.impl)
    }
    
    /// Purge a document by id from the collection. If the document doesn't exist in the collection,
    /// the NotFound error will be thrown.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func purge(id: String) throws {
        try impl.purgeDocument(withID: id)
    }
    
    // MARK: Document Expiry
    
    /// Set an expiration date to the document of the given id. Setting a nil date will clear the expiration.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func setDocumentExpiration(id: String, expiration: Date?) throws {
        try impl.setDocumentExpirationWithID(id, expiration: expiration)
    }
    
    /// Get the expiration date set to the document of the given id.
    ///
    /// Throws an NSError with the CBLError.notOpen code, if the collection is deleted or
    /// the database is closed.
    public func getDocumentExpiration(id: String) throws -> Date? {
        var error: NSError?
        let date = impl.getDocumentExpiration(withID: id, error: &error)
        if let err = error {
            throw err
        }
        return date
    }
    
    // MARK: Document Change Publisher
    
    /// Add a change listener to listen to change events occurring to a document of the given document id.
    /// To remove the listener, call remove() function on the returned listener token.
    ///
    /// If the collection is deleted or the database is closed, a warning message will be logged.
    @discardableResult public func addDocumentChangeListener(id: String,
                                   listener: @escaping (DocumentChange) -> Void) -> ListenerToken {
        return self.addDocumentChangeListener(id: id, queue: nil, listener: listener)
    }
    
    /// Add a change listener to listen to change events occurring to a document of the given document id.
    /// If a dispatch queue is given, the events will be posted on the dispatch queue. To remove the listener,
    /// call remove() function on the returned listener token.
    ///
    /// If the collection is deleted or the database is closed, a warning message will be logged.
    @discardableResult public func addDocumentChangeListener(id: String, queue: DispatchQueue?,
                                   listener: @escaping (DocumentChange) -> Void) -> ListenerToken {
        let token = impl.addDocumentChangeListener(withID: id, queue: queue)
        { [weak self] (change) in
            guard let self = self else {
                Log.log(domain: .database, level: .warning, message: "Unable to notify changes as the collection object was released")
                return
            }
            listener(DocumentChange(database: self.database,
                                    documentID: change.documentID,
                                    collection: self))
        }
        return ListenerToken(token)
    }
    
    /// Add a change listener to listen to change events occurring to any documents in the collection.
    /// To remove the listener, call remove() function on the returned listener token
    ///.
    /// If the collection is deleted or the database is closed, a warning message will be logged.
    @discardableResult public func addChangeListener(listener: @escaping (CollectionChange) -> Void) -> ListenerToken {
        return self.addChangeListener(queue: nil, listener: listener)
    }
     
    /// Add a change listener to listen to change events occurring to any documents in the collection.
    /// If a dispatch queue is given, the events will be posted on the dispatch queue.
    /// To remove the listener, call remove() function on the returned listener token.
    ///
    /// If the collection is deleted or the database is closed, a warning message will be logged.
    @discardableResult public func addChangeListener(queue: DispatchQueue?,
                                  listener: @escaping (CollectionChange) -> Void) -> ListenerToken {
        let token = impl.addChangeListener(with: queue) { [unowned self] (change) in
            listener(CollectionChange(collection: self, documentIDs: change.documentIDs))
        }
        
        return ListenerToken(token)
    }
    
    // MARK: Indexable
    
    /// Return all index names
    public func indexes() throws -> [String] {
        return try impl.indexes()
    }
    
    /// Create an index with the index name and config.
    public func createIndex(withName name: String, config: IndexConfiguration) throws {
        try impl.createIndex(withName: name, config: config.toImpl())
    }
    
    /// Create an index with the index name and index instance.
    public func createIndex(_ index: Index, name: String) throws {
        try impl.createIndex(index.toImpl(), name: name)
    }
    
    /// Delete an index by name.
    public func deleteIndex(forName name: String) throws {
        try impl.deleteIndex(withName: name)
    }
    
    // MARK: Equatable
    
    public static func == (lhs: Collection, rhs: Collection) -> Bool {
        return lhs.impl == rhs.impl
    }
    
    // MARK: Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(impl.hash)
    }
    
    // MARK: Internal
    
    init(_ impl: CBLCollection, db: Database) {
        self.impl = impl
        self.database = db
        self.scope = Scope(impl.scope, db: db)
    }
    
    var isValid: Bool { impl.isValid }
    
    let impl: CBLCollection
} 
