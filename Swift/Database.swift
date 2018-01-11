//
//  Database.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
    case none
}


/// A Couchbase Lite database.
public final class Database {
    
    /// Initializes a Couchbase Lite database with a given name and database options.
    /// If the database does not yet exist, it will be created, unless the `readOnly` option is used.
    ///
    /// - Parameters:
    ///   - name: The name of the database. May NOT contain capital letters!
    ///   - config: The database options, or nil for the default options.
    /// - Throws: An error when the database cannot be opened.
    public init(name: String, config: DatabaseConfiguration = DatabaseConfiguration.Builder().build()) throws {
        _config = config
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
    
    
    /// Saves the given mutable document to the database.
    /// If the document in the database has been updated since it was read by
    /// this Document, a conflict occurs, which will be resolved by invoking
    /// the conflict handler. This can happen if multiple application threads
    /// are writing to the database, or a pull replication is copying changes
    /// from a server.
    ///
    /// - Parameter document: The document.
    /// - Returns: The saved Document.
    /// - Throws: An error on a failure.
    @discardableResult public func saveDocument(_ document: MutableDocument) throws -> Document {
        let doc = try _impl.save(document._impl as! CBLMutableDocument)
        return Document(doc)
    }
    
    
    /// Deletes the given document. All properties are removed, and subsequent calls
    /// to the getDocument(id) method will return nil.
    /// Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
    /// change can be replicated to other databases. Thus, it does not free up all of the disk 
    /// space occupied by the document.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func deleteDocument(_ document: Document) throws {
        try _impl.delete(document._impl)
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
        return _impl.addChangeListener(with: queue) { (change) in
            listener(change)
        }
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
        return _impl.addDocumentChangeListener(withID: id, queue: queue) { (change) in
            listener(change)
        }
    }
    
    
    /// Removes a change listener with the given listener token.
    ///
    /// - Parameter token: The listener token.
    public func removeChangeListener(withToken token: ListenerToken) {
        _impl.removeChangeListener(with: token)
    }
    
    
    /// Closes a database.
    ///
    /// - Throws: An error on a failure.
    public func close() throws {
        try _impl.close()
    }
    
    
    /// Deletes a database.
    ///
    /// - Throws: An error on a failure.
    public func delete() throws {
        try _impl.delete()
    }
    
    
    /// Compacts the database file by deleting unused attachment files and
    /// vacuuming the SQLite database.
    ///
    /// - Throws: An error on a failure
    public func compact() throws {
        try _impl.compact()
    }

    
    /// Changes the database's encryption key, or removes encryption if the new key is nil.
    ///
    /// - Parameter key: The encryption key.
    /// - Throws: An error on a failure.
    public func setEncryptionKey(_ key: EncryptionKey?) throws {
        try _impl.setEncryptionKey(key?.impl)
    }
    

    /// Deletes a database of the given name in the given directory.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Throws: An error on a failure.
    public class func delete(withName name: String, inDirectory directory: String? = nil) throws {
        try CBLDatabase.delete(name, inDirectory: directory)
    }
    
    
    /// Checks whether a database of the given name exists in the given directory or not.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Returns: True if the database exists, otherwise false.
    public class func exists(withName name: String, inDirectory directory: String? = nil) -> Bool {
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
    public class func copy(fromPath path: String, toDatabase name: String,
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
    

    let _impl : CBLDatabase
    
    let _config: DatabaseConfiguration
    
}

/// ListenerToken
public typealias ListenerToken = CBLListenerToken

/// DatabaseChange
public typealias DatabaseChange = CBLDatabaseChange

/// DocumentChange
public typealias DocumentChange = CBLDocumentChange

