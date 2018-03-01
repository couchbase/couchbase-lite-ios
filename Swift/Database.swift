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

/// Log domain. The log domains here are tentative and subject to change.
public enum LogDomain: UInt8 {
    case all = 0
    case database
    case query
    case replicator
    case network
}

/// Log level. The default log level for all domains is warning.
/// The log levels here are tentative and subject to change.
public enum LogLevel: UInt8 {
    case debug = 0
    case verbose
    case info
    case warning
    case error
    case lastWriteWins
}


/// Concurruncy control type used when saving or deleting a document.
///
/// - lastWriteWins: The last write operation will win if there is a conflict.
/// - failOnConflict: The operation will fail if there is a conflict.
public enum ConcurrencyControl: UInt8 {
    case lastWriteWins = 0
    case failOnConflict
}


/// A Couchbase Lite database.
public final class Database {
    
    /// Initializes a Couchbase Lite database with a given name and database options.
    /// If the database does not yet exist, it will be created, unless the `readOnly` option is used.
    ///
    /// - Parameters:
    ///   - name: The name of the database.
    ///   - config: The database options, or nil for the default options.
    /// - Throws: An error when the database cannot be opened.
    public init(name: String, config: DatabaseConfiguration = DatabaseConfiguration()) throws {
        _config = DatabaseConfiguration(config: config, readonly: true)
        _impl = try CBLDatabase(name: name, config: _config.toImpl())
    }
    
    
    /// The database's name.
    public var name: String { return _impl.name }
    
    
    /// The database's path. If the database is closed or deleted, nil value will be returned.
    public var path: String? { return _impl.path }
    
    
    /// The total numbers of documents in the database.
    public var count: UInt64 { return _impl.count }
    
    
    /// The database configuration.
    public var config: DatabaseConfiguration {
        return _config
    }
    
    
    /// Gets a Document object with the given ID.
    public func document(withID id: String) -> Document? {
        if let implDoc = _impl.document(withID: id) {
            return Document(implDoc)
        }
        return nil;
    }
    
    
    /// Gets document fragment object by the given document ID.
    public subscript(key: String) -> DocumentFragment {
        return DocumentFragment(_impl[key])
    }
    
    
    /// Saves a document to the database. When write operations are executed
    /// concurrently, the last writer will overwrite all other written values.
    /// Calling this function is the same as calling the saveDocument(document,
    /// concurrencyControl) function with ConcurrencyControl.lastWriteWins.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func saveDocument(_ document: MutableDocument) throws {
        try _impl.save(document._impl as! CBLMutableDocument)
    }
    
    
    /// Saves a document to the database. When used with lastWriteWins concurrency
    /// control, the last write operation will win if there is a conflict. When used
    /// with failOnConflict concurrency control, save will fail with 'false' value
    /// returned.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - concurrencyControl: The concurrency control.
    /// - Returns: True if successful. False if the failOnConflict concurrency
    ///            control is used, and there is a conflict.
    /// - Throws: An error on a failure.
    @discardableResult public func saveDocument(
        _ document: MutableDocument, concurrencyControl: ConcurrencyControl) throws -> Bool {
        do {
            let cc = concurrencyControl == .lastWriteWins ?
                CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict;
            try _impl.save(document._impl as! CBLMutableDocument, concurrencyControl: cc)
            return true
        } catch let err as NSError {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
    }
    
    
    /// Deletes a document from the database. When write operations are executed
    /// concurrently, the last writer will overwrite all other written values.
    /// Calling this function is the same as calling the deleteDocument(document,
    /// concurrencyControl) function with ConcurrencyControl.lastWriteWins.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func deleteDocument(_ document: Document) throws {
        try _impl.delete(document._impl)
    }
    
    
    /// Deletes a document from the database. When used with lastWriteWins concurrency
    /// control, the last write operation will win if there is a conflict.
    /// When used with failOnConflict concurrency control, save will fail with
    /// 'false' value returned.
    ///
    /// - Parameters:
    ///   - document: The document.
    ///   - concurrencyControl: The concurrency control.
    /// - Returns: True if successful. False if the failOnConflict concurrency
    ///            control is used, and there is a conflict.
    /// - Throws: An error on a failure.
    @discardableResult public func deleteDocument(
        _ document: Document, concurrencyControl: ConcurrencyControl) throws -> Bool {
        do {
            let cc = concurrencyControl == .lastWriteWins ?
                CBLConcurrencyControl.lastWriteWins : CBLConcurrencyControl.failOnConflict;
            try _impl.delete(document._impl, concurrencyControl: cc)
            return true
        } catch let err as NSError {
            if err.code == CBLErrorConflict {
                return false
            }
            throw err
        }
    }
    
    
    /// Purges the given document from the database.
    /// This is more drastic than deletion: it removes all traces of the document.
    /// The purge will NOT be replicated to other databases.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func purgeDocument(_ document: Document) throws {
        try _impl.purgeDocument(document._impl)
    }
    
    
    /// Runs a group of database operations in a batch. Use this when performing bulk write 
    /// operations like multiple inserts/updates; it saves the overhead of multiple database 
    /// commits, greatly improving performance.
    ///
    /// - Parameter block: The block to be executed as a batch operations.
    /// - Throws: An error on a failure.
    public func inBatch(using block: () throws -> Void ) throws {
        var caught: Error? = nil
        try _impl.inBatch(usingBlock: {
            do {
                try block()
            } catch let error {
                caught = error
            }
        })
        if let caught = caught {
            throw caught
        }
    }
    
    
    /// Adds a database change listener. Changes will be posted on the main queue.
    ///
    /// - Parameter listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addChangeListener(
        _ listener: @escaping (DatabaseChange) -> Void) -> ListenerToken
    {
        return self.addChangeListener(withQueue: nil, listener: listener)
    }
    
    
    /// Adds a database change listener with the dispatch queue on which changes
    /// will be posted. If the dispatch queue is not specified, the changes will be
    /// posted on the main queue.
    ///
    /// - Parameters:
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult  public func addChangeListener(withQueue queue: DispatchQueue?,
        listener: @escaping (DatabaseChange) -> Void) -> ListenerToken
    {
        let token = _impl.addChangeListener(with: queue) { (change) in
            listener(DatabaseChange(database: self, documentIDs: change.documentIDs))
        }
        return ListenerToken(token)
    }
    
    
    /// Adds a document change listener block for the given document ID.
    ///
    /// - Parameters:
    ///   - documentID: The document ID.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addDocumentChangeListener(withID id: String,
        listener: @escaping (DocumentChange) -> Void) -> ListenerToken
    {
        return self.addDocumentChangeListener(withID: id, queue: nil, listener: listener)
    }
    
    
    
    /// Adds a document change listener for the document with the given ID and the
    /// dispatch queue on which changes will be posted. If the dispatch queue
    /// is not specified, the changes will be posted on the main queue.
    ///
    /// - Parameters:
    ///   - id: The document ID.
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addDocumentChangeListener(withID id: String,
        queue: DispatchQueue?, listener: @escaping (DocumentChange) -> Void) -> ListenerToken
    {
        let token = _impl.addDocumentChangeListener(withID: id, queue: queue) { (change) in
            listener(DocumentChange(database: self, documentID: change.documentID))
        }
        return ListenerToken(token)
    }
    
    
    /// Removes a change listener with the given listener token.
    ///
    /// - Parameter token: The listener token.
    public func removeChangeListener(withToken token: ListenerToken) {
        _impl.removeChangeListener(with: token._impl)
    }
    
    
    /// Closes a database.
    ///
    /// - Throws: An error on a failure.
    public func close() throws {
        try _impl.close()
        stopActiveQueries()
    }
    
    
    /// Deletes a database.
    ///
    /// - Throws: An error on a failure.
    public func delete() throws {
        try _impl.delete()
        stopActiveQueries()
    }
    
    
    /// Compacts the database file by deleting unused attachment files and
    /// vacuuming the SQLite database.
    ///
    /// - Throws: An error on a failure
    public func compact() throws {
        try _impl.compact()
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
    
    
    /// Set log level for the given log domain.
    ///
    /// - Parameters:
    ///   - level: The log level.
    ///   - domain: The log domain.
    public class func setLogLevel(_ level: LogLevel, domain: LogDomain) {
        let l = CBLLogLevel.init(rawValue: UInt32(level.rawValue))!
        let d = CBLLogDomain.init(rawValue: UInt32(domain.rawValue))!
        return CBLDatabase.setLogLevel(l, domain: d)
    }
    
    
    // MARK: Internal
    
    
    func addReplicator(_ replicator: Replicator) {
        _lock.lock()
        _activeReplicators.add(replicator)
        _lock.unlock()
    }
    
    
    func removeReplicator(_ replicator: Replicator) {
        _lock.lock()
        _activeReplicators.remove(replicator)
        _lock.unlock()
    }
    
    
    func addQuery(_ query: Query) {
        _lock.lock()
        _activeQueries.add(query)
        _lock.unlock()
    }
    
    
    func removeQuery(_ query: Query) {
        _lock.lock()
        _activeQueries.remove(query)
        _lock.unlock()
    }
    
    
    private func stopActiveQueries() {
        _lock.lock()
        for query in _activeQueries.allObjects {
            (query as! Query).stop()
        }
        _lock.unlock()
    }
    
    private let _config: DatabaseConfiguration
    
    private var _lock = NSRecursiveLock()
    
    private let _activeReplicators = NSMutableSet()
    
    private let _activeQueries = NSMutableSet()

    let _impl: CBLDatabase
}
