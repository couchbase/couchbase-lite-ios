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
import CouchbaseLiteSwift_Private

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
        self.config = DatabaseConfiguration(config: config)
        self.impl = try CBLDatabase(name: name, config: self.config.toImpl())
    }
    
    /// The database's name.
    public var name: String { return impl.name }
    
    /// The database's path. If the database is closed or deleted, nil value will be returned.
    public var path: String? { return impl.path }
    
    /// The database configuration.
    public let config: DatabaseConfiguration
    
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
    
    /// The same as ``inBatch(using:)``, but the closure can return a Bool.
    /// If the closure returns `false`, the transaction will be aborted, and this function will return false.
    internal func maybeBatch(using block: () throws -> Bool ) throws -> Bool {
        return try impl.maybeBatch {
            return try block()
        }
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
    
    /// The same as `inBatch(() -> Void)`, but the closure can return a Bool.
    /// If the closure returns `false`, the transaction will be aborted, and this function will return false.
    internal func maybeBatch(block: () throws -> Bool) throws -> Bool {
        var err: NSError? = nil
        guard __maybeBatch(&err, usingBlockWithError: { (errPtr) -> Bool in
            do {
                return try block()
            } catch {
                errPtr?.pointee = error as NSError
                return false
            }
        }) else {
            if let err = err {
                throw err
            }
            return false
        }
        return true
    }
}
