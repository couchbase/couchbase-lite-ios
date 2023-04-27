//
//  Database.swift
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

/// Concurruncy control type used when saving or deleting a document.
///
/// - lastWriteWins: The last write operation will win if there is a conflict.
/// - failOnConflict: The operation will fail if there is a conflict.
public enum ConcurrencyControl: UInt8 {
    case lastWriteWins = 0
    case failOnConflict
}

/// Maintenance Type used when performing database maintenance
///
/// - compact: Compact the database file and delete unused attachments.
/// - reindex: (Volatile API) Rebuild the entire database's indexes.
/// - integrityCheck: (Volatile API) Check for the database’s corruption. If found, an error will be returned.
/// - optimize: Quickly updates database statistics that may help optimize queries that have been run by this Database since it was opened
/// - fullOptimize: Fully scans all indexes to gather database statistics that help optimize queries.
public enum MaintenanceType: UInt8 {
    case compact = 0
    case reindex
    case integrityCheck
    case optimize
    case fullOptimize
}

/// A Couchbase Lite database.
public final class Database {
    /// The default scope name constant
    public static let defaultScopeName: String = kCBLDefaultScopeName
    
    /// The default collection name constant
    public static let defaultCollectionName: String = kCBLDefaultCollectionName
    
    /// Initializes a Couchbase Lite database with a given name and database options.
    /// If the database does not yet exist, it will be created, unless the `readOnly` option is used.
    ///
    /// - Parameters:
    ///   - name: The name of the database.
    ///   - config: The database options, or nil for the default options.
    /// - Throws: An error when the database cannot be opened.
    public init(name: String, config: DatabaseConfiguration = DatabaseConfiguration()) throws {
        CBLDatabase.checkFileLogging(true);
        self.config = DatabaseConfiguration(config: config)
        self.impl = try CBLDatabase(name: name, config: self.config.toImpl())
    }
    
    /// The database's name.
    public var name: String { return impl.name }
    
    /// The database's path. If the database is closed or deleted, nil value will be returned.
    public var path: String? { return impl.path }
    
    /// The total numbers of documents in the database.
    @available(*, deprecated, message: "Use database.defaultCollection().count instead.")
    public var count: UInt64 { return impl.count }
    
    /// The database configuration.
    public let config: DatabaseConfiguration
    
    /// Gets a document from the default collection by document ID.
    /// If the document doesn't exist, nil will be returned.
    @available(*, deprecated, message: "Use database.defaultCollection().document(id:) instead.")
    public func document(withID id: String) -> Document? {
        guard let col = try? defaultCollection() else {
            Database.throwNotOpenError()
        }
        
        if let implDoc = impl.document(withID: id)  {
            return Document(implDoc, collection: col)
        }
        
        return nil
    }
    
    /// Gets document fragment object from the default collection by document ID.
    @available(*, deprecated, message: "Use database.defaultCollection().subscript(key:) instead.")
    public subscript(key: String) -> DocumentFragment {
        guard let col = try? defaultCollection() else {
            Database.throwNotOpenError()
        }
        return DocumentFragment(impl[key], collection: col)
    }
    
    /// Saves a document to the default collection. When write operations are executed
    /// concurrently, the last writer will overwrite all other written values.
    /// Calling this function is the same as calling the saveDocument(document,
    /// concurrencyControl) function with ConcurrencyControl.lastWriteWins.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().save(:) instead.")
    public func saveDocument(_ document: MutableDocument) throws {
        try impl.save(document.impl as! CBLMutableDocument)
    }
    
    /// Saves a document to the default collection. When used with lastWriteWins
    /// concurrency control, the last write operation will win if there is a conflict.
    /// When used with failOnConflict concurrency control, save will fail with 'false' value
    /// returned.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - concurrencyControl: The concurrency control.
    /// - Returns: True if successful. False if the failOnConflict concurrency
    ///            control is used, and there is a conflict.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().save(:concurrencyControl:) instead.")
    @discardableResult public func saveDocument(
        _ document: MutableDocument, concurrencyControl: ConcurrencyControl) throws -> Bool
    {
        do {
            let cc = concurrencyControl == .lastWriteWins ?
            CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict;
            try impl.save(document.impl as! CBLMutableDocument, concurrencyControl: cc)
            return true
        } catch let err as NSError {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
    }
    
    /// Saves a document to the default collection. When write operations are executed concurrently
    /// and if conflicts occur, the conflict handler will be called. Use the conflict handler to directly
    /// edit the document to resolve the conflict. When the conflict handler returns 'true', the
    /// save method will save the edited document as the resolved document. If the conflict handler
    /// returns 'false', the save operation will be canceled with 'false' value returned as
    /// the conflict wasn't resolved.
    /// 
    /// - Parameters:
    ///   - document: The document.
    ///   - conflictHandler: The conflict handler closure which can be used to resolve it.
    /// - Returns: True if successful. False if there is a conflict, but the conflict wasn't
    ///            resolved as the conflict handler returns 'false' value.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().save(:conflictHandler:) instead.")
    @discardableResult public func saveDocument(
        _ document: MutableDocument, conflictHandler: @escaping (MutableDocument, Document?) -> Bool
    ) throws -> Bool {
        do {
            try impl.save(
                document.impl as! CBLMutableDocument,
                conflictHandler: { (cur: CBLMutableDocument, old: CBLDocument?) -> Bool in
                    guard let col = try? self.defaultCollection() else {
                        Database.throwNotOpenError()
                    }
                    return conflictHandler(document, old != nil ? Document(old!, collection: col) : nil)
                }
            )
            return true
        } catch let err as NSError {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
    }
    
    /// Deletes a document from the default collection. When write operations are executed
    /// concurrently, the last writer will overwrite all other written values.
    /// Calling this function is the same as calling the deleteDocument(document,
    /// concurrencyControl) function with ConcurrencyControl.lastWriteWins.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().delete(:) instead.")
    public func deleteDocument(_ document: Document) throws {
        try impl.delete(document.impl)
    }
    
    /// Deletes a document from the default collection. When used with lastWriteWins
    /// concurrency control, the last write operation will win if there is a conflict.
    /// When used with failOnConflict concurrency control, save will fail with
    /// 'false' value returned.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - concurrencyControl: The concurrency control.
    /// - Returns: True if successful. False if the failOnConflict concurrency
    ///            control is used, and there is a conflict.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().delete(:concurrencyControl:) instead.")
    @discardableResult public func deleteDocument(
        _ document: Document, concurrencyControl: ConcurrencyControl) throws -> Bool
    {
        do {
            let cc = concurrencyControl == .lastWriteWins ?
            CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict;
            try impl.delete(document.impl, concurrencyControl: cc)
            return true
        } catch let err as NSError {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
    }
    
    /// Purges the given document from the default collection.
    /// This is more drastic than deletion: it removes all traces of the document.
    /// The purge will NOT be replicated to other databases.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().purge(:) instead.")
    public func purgeDocument(_ document: Document) throws {
        try impl.purgeDocument(document.impl)
    }
    
    /// Purges the document with the given documentID from the default collection.
    /// This is more drastic than deletion: it removes all traces of the document.
    /// The purge will NOT be replicated to other databases.
    ///
    /// - Parameter documentID: The document.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().purge(id:) instead.")
    public func purgeDocument(withID documentID: String) throws {
        try impl.purgeDocument(withID: documentID)
    }
    
    /// Save a blob object directly into the database without associating it with any documents.
    ///
    /// Note: Blobs that are not associated with any documents will be removed from the database
    /// when compacting the database.
    ///
    /// - Parameter blob: The blob to save.
    /// - Throws: An error on a failure.
    public func saveBlob(blob: Blob) throws {
        try impl.save(blob.impl)
    }
    
    /// Get a blob object using a blob’s metadata.
    /// If the blob of the specified metadata doesn’t exist, the nil value will be returned.
    ///
    /// - Parameter properties: The properties for getting the blob object. If dictionary is not valid, it will
    /// throw InvalidArgument exception. See the note section
    /// - Throws: An error on a failure.
    ///
    /// - Note:
    /// Key            | Value                     | Mandatory | Description
    /// ----------------------------------------------------------------------------------
    /// @type          | constant string "blob"    | Yes       | Indicate Blob data type.
    /// content_type   | String                    | No        | Content type ex. text/plain.
    /// length         | Number                    | No        | Binary length of the Blob in bytes.
    /// digest         | String                    | Yes       | The cryptographic digest of the Blob's content.
    public func getBlob(properties: [String: Any]) throws -> Blob? {
        guard let blobImp = impl.getBlob(properties) else {
            return nil
        }
        
        return Blob(blobImp)
    }
    
    /// Runs a group of database operations in a batch. Use this when performing bulk write 
    /// operations like multiple inserts/updates; it saves the overhead of multiple database 
    /// commits, greatly improving performance.
    ///
    /// - Parameter block: The block to be executed as a batch operations.
    /// - Throws: An error on a failure.
    public func inBatch(using block: () throws -> Void ) throws {
        try impl.inBatch {
            try block()
        }
    }
    
    /// Sets an expiration date on a document in the default collection.
    /// After this time the document will be purged from the default collection.
    ///
    /// - Parameters:
    ///     - documentID: The ID of the document to set the expiration date for
    ///     - expiration: The expiration date. Set nil date will reset the document expiration.
    /// - Throws: An error on a failure.
    @available(*, deprecated, message: "Use database.defaultCollection().setDocumentExpiration(id:expiration:) instead.")
    public func setDocumentExpiration(withID documentID: String, expiration: Date?) throws {
        try impl.setDocumentExpirationWithID(documentID, expiration: expiration)
    }
    
    /// Returns the expiration time of a document in the default collection, if exists, else nil.
    ///
    /// - Parameter documentID: The ID of the document to set the expiration date for.
    /// - Returns: the expiration time of a document, if one has been set, else nil.
    @available(*, deprecated, message: "Use database.defaultCollection().getDocumentExpiration(id:) instead.")
    public func getDocumentExpiration(withID documentID: String) -> Date? {
        return impl.getDocumentExpiration(withID: documentID)
    }
    
    /// Adds a change listener to listen to changes in the default collection.
    /// Changes will be posted on the main queue.
    ///
    /// - Parameter listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @available(*, deprecated, message: "Use database.defaultCollection().addChangeListener(:) instead.")
    @discardableResult public func addChangeListener(
        _ listener: @escaping (DatabaseChange) -> Void) -> ListenerToken
    {
        return self.addChangeListener(withQueue: nil, listener: listener)
    }
    
    /// Adds a change listener with the dispatch queue on which changes
    /// will be posted to listen to changes in the default collection. If the dispatch queue is not specified,
    /// the changes will be posted on the main queue.
    ///
    /// - Parameters:
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @available(*, deprecated, message: "Use database.defaultCollection().addChangeListener(queue:listener:) instead.")
    @discardableResult  public func addChangeListener(withQueue queue: DispatchQueue?,
        listener: @escaping (DatabaseChange) -> Void) -> ListenerToken
    {
        let token = impl.addChangeListener(with: queue) { [unowned self] (change) in
            listener(DatabaseChange(database: self, documentIDs: change.documentIDs))
        }
        return ListenerToken(token)
    }
    
    /// Adds a document change listener for the document with the given document ID in the default collection.
    ///
    /// - Parameters:
    ///   - documentID: The document ID.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @available(*, deprecated, message: "Use database.defaultCollection().addDocumentChangeListener(id:listener:) instead.")
    @discardableResult public func addDocumentChangeListener(withID id: String,
        listener: @escaping (DocumentChange) -> Void) -> ListenerToken
    {
        return self.addDocumentChangeListener(withID: id, queue: nil, listener: listener)
    }
    
    /// Adds a document change listener for the document with the given document ID in the default collection with the dispatch queue
    /// on which changes will be posted . If the dispatch queue is not specified, the changes will be posted on the main queue.
    ///
    /// - Parameters:
    ///   - id: The document ID.
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @available(*, deprecated, message: "Use database.defaultCollection().addDocumentChangeListener(id:queue:listener:) instead.")
    @discardableResult public func addDocumentChangeListener(withID id: String,
                                                             queue: DispatchQueue?,
                                                             listener: @escaping (DocumentChange) -> Void) -> ListenerToken
    {
        let token = impl.addDocumentChangeListener(withID: id, queue: queue) { (change) in
            listener(DocumentChange(database: self,
                                    documentID: change.documentID,
                                    collection: Collection(change.collection, db: self)))
        }
        return ListenerToken(token)
    }
    
    /// Removes a change listener with the given listener token.
    ///
    /// - Parameter token: The listener token.
    @available(*, deprecated, message: "Use token.remove() instead.")
    public func removeChangeListener(withToken token: ListenerToken) {
        impl.removeChangeListener(with: token.impl)
    }
    
    /// Close database synchronously. Before closing the database, the active replicators, listeners and live queries will be stopped.
    ///
    /// - Throws: An error on a failure.
    public func close() throws {
        try impl.close()
        stopActiveQueries()
    }
    
    /// Close and delete the database synchronously. Before closing the database, the active replicators, listeners and live queries
    /// will be stopped.
    ///
    /// - Throws: An error on a failure.
    public func delete() throws {
        try impl.delete()
        stopActiveQueries()
    }
    
    /// Performs database maintenance.
    ///
    /// - Throws: An error on a failure
    public func performMaintenance(type: MaintenanceType) throws {
        try impl.perform(CBLMaintenanceType(rawValue: UInt32(type.rawValue))!)
    }

    /// Deletes a database of the given name in the given directory.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Throws: An error on a failure.
    public static func delete(withName name: String, inDirectory directory: String? = nil) throws {
        try CBLDatabase.delete(name, inDirectory: directory)
    }
    
    /// Checks whether a database of the given name exists in the given directory or not.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Returns: True if the database exists, otherwise false.
    public static func exists(withName name: String, inDirectory directory: String? = nil) -> Bool {
        return CBLDatabase.databaseExists(name, inDirectory: directory)
    }
    
    /// Copies a canned databaes from the given path to a new database with the given name and
    /// the configuration. The new database will be created at the directory specified in the
    /// configuration. Without given the database configuration, the default configuration that
    /// is equivalent to setting all properties in the configuration to nil will be used.
    ///
    /// - Note: This method will copy the database without changing the encryption key of the
    /// original database. The encryption key specified in the given config is the encryption key
    /// used for both the original and copied database. To change or add the encryption key for
    /// the copied database, call Database.changeEncryptionKey(key) for the copy.
    /// - Note: It is recommended to close the source database before calling this method.
    ///
    /// - Parameters:
    ///   - path: The source database path.
    ///   - name: The name of the new database to be created.
    ///   - config: The database configuration for the new database name.
    /// - Throws: An error on a failure.
    public static func copy(fromPath path: String, toDatabase name: String,
                           withConfig config: DatabaseConfiguration?) throws
    {
        try CBLDatabase.copy(fromPath: path, toDatabase: name, withConfig: config?.toImpl())
    }
    
    /// Log object used for configuring console, file, and custom logger.
    public static let log = Log()
    
    
    // MARK: Scopes
    
    
    /// Get the default scope.
    public func defaultScope() throws -> Scope {
        let s = try impl.defaultScope()
        return Scope(s, db: self)
    }
    
    /// Get scope names that have at least one collection.
    /// Note: the default scope is exceptional as it will always be listed even though there are no collections
    /// under it.
    public func scopes() throws -> [Scope] {
        var scopes = [Scope]()
        let res = try impl.scopes()
        for s in res {
            scopes.append(Scope(s, db: self))
        }
        return scopes
    }
    
    /// Get a scope object by name. As the scope cannot exist by itself without having a collection, the nil
    /// value will be returned if there are no collections under the given scope’s name.
    /// Note: The default scope is exceptional, and it will always be returned.
    public func scope(name: String) throws -> Scope? {
        var error: NSError?
        let s = impl.scope(withName: name, error: &error)
        if let err = error {
            throw err
        }
        
        if let scope = s {
            return Scope(scope, db: self)
        }
        
        return nil
    }
    
    // MARK: Collections
    
    /// Get the default collection.
    public func defaultCollection() throws  -> Collection {
        let c = try impl.defaultCollection()
        return Collection(c, db: self)
    }

    /// Get all collections in the specified scope.
    public func collections(scope: String? = defaultScopeName) throws -> [Collection] {
        var collections = [Collection]()
        let res = try impl.collections(scope)
        for c in res {
            collections.append(Collection(c, db: self))
        }
        return collections
    }
    
    /// Create a named collection in the specified scope.
    /// If the collection already exists, the existing collection will be returned.
    public func createCollection(name: String, scope: String? = defaultScopeName) throws -> Collection {
        let result = try impl.createCollection(withName: name, scope: scope)
        return Collection(result, db: self)
    }

    /// Get a collection in the specified scope by name.
    /// If the collection doesn't exist, a nil value will be returned.
    public func collection(name: String, scope: String? = defaultScopeName) throws -> Collection? {
        var error: NSError?
        let result = impl.collection(withName: name, scope: scope, error: &error)
        if let err = error {
            throw err
        }
        
        if let res = result {
            return Collection(res, db: self)
        }
        
        return nil
    }
    
    /// Delete a collection by name  in the specified scope. If the collection doesn't exist, the operation will be no-ops.
    /// 
    /// - Note: The default collection cannot be deleted.
    public func deleteCollection(name: String, scope: String? = defaultScopeName) throws {
        try impl.deleteCollection(withName: name, scope: scope)
    }

    
    // MARK: Internal
    
    func addReplicator(_ replicator: Replicator) {
        lock.lock()
        activeReplicators.add(replicator)
        lock.unlock()
    }
    
    func removeReplicator(_ replicator: Replicator) {
        lock.lock()
        activeReplicators.remove(replicator)
        lock.unlock()
    }
    
    func addQuery(_ query: Query) {
        lock.lock()
        activeQueries.add(query)
        lock.unlock()
    }
    
    func removeQuery(_ query: Query) {
        lock.lock()
        activeQueries.remove(query)
        lock.unlock()
    }
    
    private func stopActiveQueries() {
        lock.lock()
        for query in activeQueries.allObjects {
            (query as! Query).stop()
        }
        lock.unlock()
    }
    
    static func throwNotOpenError() -> Never {
        fatalError("The database was closed or released, or the default collection was deleted.");
    }
    
    let impl: CBLDatabase
    
    private var lock = NSRecursiveLock()
    
    private let activeReplicators = NSMutableSet()
    
    private let activeQueries = NSMutableSet()
}

extension CBLDatabase {
    func inBatch(block: () throws -> Void) throws -> Void {
        try __inBatch(usingBlockWithError: { (errPtr) in
            do {
                try block()
            } catch {
                errPtr?.pointee = error as NSError
            }
        })
    }
}
