//
//  Database.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A database encryption key consists of a password string, or a 32-byte AES256 key.
///
/// - password: Password string
/// - aes256: 32-byte AES256 data key
public enum EncryptionKey {
    case password (String)
    case aes256   (Data)
    
    var asObject: Any {
        switch (self) {
        case .password(let pwd):
            return pwd
        case .aes256 (let data):
            return data
        }
    }
}


/// Options for opening a database. All properties default to NO or nil.
public struct DatabaseConfiguration {
    
    /// Initialize a DatabaseConfiguration with the default configuration.
    public init() { }
    
    /// Path to the directory to store the database in. If the directory doesn't already exist it
    /// will be created when the database is opened.
    /// A nil value (the default) means to use the default directory, in Application Support. You
    /// won't usually need to change this.
    public var directory: String? {
        mutating get {
            if _directory == nil {
                _directory = CBLDatabaseConfiguration().directory
            }
            return _directory
        }
        set {
            _directory = newValue
        }
    }
    
    /// The conflict resolver for this database.
    /// If nil, a default algorithm will be used, where the revision with more history wins.
    /// An individual document can override this for itself by setting its own property.
    public var conflictResolver: ConflictResolver?

    /// A key to encrypt the database with. If the database does not exist and is being created, it
    /// will use this key, and the same key must be given every time it's opened.
    ///
    /// * The primary form of key is an NSData object 32 bytes in length: this is interpreted as a raw
    ///   AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
    ///   like SecRandomCopyBytes or CCRandomGenerateBytes.
    /// * Alternatively, the value may be an NSString containing a passphrase. This will be run through
    ///   64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
    /// * A default nil value, of course, means the database is unencrypted.
    public var encryptionKey: EncryptionKey?
    
    /// File protection/encryption options (iOS only.)
    /// Defaults to whatever file protection settings you've specified in your app's entitlements.
    /// Specifying a nonzero value here overrides those settings for the database files.
    /// If file protection is at the highest level, NSDataWritingFileProtectionCompleteUnlessOpen or
    /// NSDataWritingFileProtectionComplete, it will not be possible to read or write the database
    /// when the device is locked. This can make it impossible to run replications in the background
    /// or respond to push notifications.
    public var fileProtection: NSData.WritingOptions = []
    
    // MARK: Internal
    
    var _directory: String?
    
    func toImpl() -> CBLDatabaseConfiguration {
        let config = CBLDatabaseConfiguration()
        
        if let dir = _directory {
            config.directory = dir
        }
        
        if let cr = self.conflictResolver {
            config.conflictResolver = BridgingConflictResolver(resolver: cr)
        }
        
        config.encryptionKey = self.encryptionKey?.asObject
        
        config.fileProtection = self.fileProtection
        
        return config
    }
    
    class BridgingConflictResolver: NSObject, CBLConflictResolver {
        let _resovler: ConflictResolver
        
        init(resolver: ConflictResolver) {
            _resovler = resolver
        }
        
        public func resolve(_ conflict: CBLConflict) -> CBLReadOnlyDocument? {
            let resolved = _resovler.resolve(conflict: Conflict(impl: conflict))
            return resolved?._impl as? CBLReadOnlyDocument
        }
    }
    
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
    public init(name: String, config: DatabaseConfiguration = DatabaseConfiguration()) throws {
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
    public func getDocument(_ id: String) -> Document? {
        if let implDoc = _impl.document(withID: id) {
            return Document(implDoc)
        }
        return nil;
    }
    
    
    /// Checks whether the document of the given ID exists in the database or not.
    public func contains(_ docID: String) -> Bool {
        return _impl.contains(docID)
    }
    
    
    /// Gets document fragment object by the given document ID.
    public subscript(id: String) -> DocumentFragment {
        return DocumentFragment(_impl[id])
    }
    
    
    /// Saves the given document to the database.
    /// If the document in the database has been updated since it was read by this Document, a
    /// conflict occurs, which will be resolved by invoking the conflict handler. This can happen 
    /// if multiple application threads are writing to the database, or a pull replication 
    //  is copying changes from a server.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func save(_ document: Document) throws {
        try _impl.save(document._impl as! CBLDocument)
    }
    
    
    /// Deletes the given document. All properties are removed, and subsequent calls
    /// to the getDocument(id) method will return nil.
    /// Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
    /// change can be replicated to other databases. Thus, it does not free up all of the disk 
    /// space occupied by the document.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func delete(_ document: Document) throws {
        try _impl.delete(document._impl as! CBLDocument)
    }
    
    
    /// Purges the given document from the database.
    /// This is more drastic than deletion: it removes all traces of the document.
    /// The purge will NOT be replicated to other databases.
    ///
    /// - Parameter document: The document.
    /// - Throws: An error on a failure.
    public func purge(_ document: Document) throws {
        try _impl.purgeDocument(document._impl as! CBLDocument)
    }
    
    
    /// Runs a group of database operations in a batch. Use this when performing bulk write 
    /// operations like multiple inserts/updates; it saves the overhead of multiple database 
    /// commits, greatly improving performance.
    ///
    /// - Parameter block: The block to be executed as a batch operations.
    /// - Throws: An error on a failure.
    public func inBatch(_ block: () throws -> Void ) throws {
        var caught: Error? = nil
        try _impl.inBatch(do: {
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
    
    
    /// Adds a database change listener block.
    ///
    /// - Parameter block: The block to be executed when the change is received.
    /// - Returns: An opaque object to act as the listener and for removing the listener
    ///            when calling the removeChangeListener() method.
    @discardableResult public func addChangeListener(_ block: @escaping (DatabaseChange) -> Void)
        -> NSObjectProtocol
    {
        return _impl.addChangeListener({ (change) in
            block(change)
        })
    }
    
    
    /// Adds a document change listener block for the given document ID.
    ///
    /// - Parameters:
    ///   - documentID: The document ID.
    ///   - block: The block to be executed when the change is received.
    /// - Returns: An opaque object to act as the listener and for removing the listener
    ///            when calling the removeChangeListener() method.
    public func addChangeListener(documentID: String,
                                  using block: @escaping (DocumentChange) -> Void) -> NSObjectProtocol
    {
        return _impl.addChangeListener(forDocumentID: documentID) { (change) in
            block(change)
        }
    }
    
    
    /// Removes a change listener. The given change listener is the opaque object 
    /// returned by the addChangeListener() method.
    ///
    /// - Parameter listener: The listener object to be removed.
    public func removeChangeListener(_ listener: NSObjectProtocol) {
        _impl.removeChangeListener(listener)
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

    
    /// Changes the database's encryption key, or removes encryption if the new key is nil
    ///
    /// - Parameter key: The encryption key in the form of an NSString (a password) or an
    ///                  NSData object exactly 32 bytes in length (a raw AES key.) If a string 
    ///                  is given, it will be internally converted to a raw key using 64,000 
    ///                  rounds of PBKDF2 hashing. A nil value will decrypt the database.
    /// - Throws: An error on a failure
    public func changeEncryptionKey(_ key: EncryptionKey?) throws {
        try _impl.changeEncryptionKey(key?.asObject)
    }
    

    /// Deletes a database of the given name in the given directory.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Throws: An error on a failure.
    public class func delete(_ name: String, inDirectory directory: String? = nil) throws {
        try CBLDatabase.delete(name, inDirectory: directory)
    }
    
    
    /// Checks whether a database of the given name exists in the given directory or not.
    ///
    /// - Parameters:
    ///   - name: The database name.
    ///   - directory: The directory where the database is located at.
    /// - Returns: True if the database exists, otherwise false.
    public class func exists(_ name: String, inDirectory directory: String? = nil) -> Bool {
        return CBLDatabase.databaseExists(name, inDirectory: directory)
    }

    
    // MARK: Internal
    

    let _impl : CBLDatabase
    
    let _config: DatabaseConfiguration
    
}

/// DatabaseChange
public typealias DatabaseChange = CBLDatabaseChange

/// DocumentChange
public typealias DocumentChange = CBLDocumentChange
