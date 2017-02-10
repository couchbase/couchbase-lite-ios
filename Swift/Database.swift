//
//  Database.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


public typealias ConflictResolver = CBLConflictResolver


/** A database encryption key consists of a password string, or a 32-byte AES256 key. */
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


/** Options for opening a database. All properties default to NO or nil. */
public struct DatabaseOptions {

    /** Path to the directory to store the database in. If the directory doesn't already exist it will
         be created when the database is opened.
         A nil value (the default) means to use the default directory, in Application Support. You
         won't usually need to change this. */
    public var directory: String? = nil

    /** File protection/encryption options (iOS only.)
         Defaults to whatever file protection settings you've specified in your app's entitlements.
         Specifying a nonzero value here overrides those settings for the database files.
         If file protection is at the highest level, NSDataWritingFileProtectionCompleteUnlessOpen or
         NSDataWritingFileProtectionComplete, it will not be possible to read or write the database
         when the device is locked. This can make it impossible to run replications in the background
         or respond to push notifications. */
    public var fileProtection: NSData.WritingOptions = []

    /** A key to encrypt the database with. If the database does not exist and is being created, it
         will use this key, and the same key must be given every time it's opened.

         * The primary form of key is an NSData object 32 bytes in length: this is interpreted as a raw
         AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
         like SecRandomCopyBytes or CCRandomGenerateBytes.
         * Alternatively, the value may be an NSString containing a passphrase. This will be run through
         64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
         * A default nil value, of course, means the database is unencrypted. */
    public var encryptionKey: EncryptionKey? = nil

    /** If YES, the database will be opened read-only. */
    public var readOnly: Bool = false
}


public typealias IndexType = CBLIndexType

/** Specifies the type of index to create, and parameters for certain types of indexes. */
public enum IndexOptions {
    case valueIndex
    case fullTextIndex (language: String?, ignoreDiacritics: Bool)
    case geoIndex
}



/** A Couchbase Lite database. */
public final class Database {

    /** Initializes a Couchbase Lite database with a given name and database options.
         If the database does not yet exist, it will be created, unless the `readOnly` option is used.
         @param name  The name of the database. May NOT contain capital letters!
         @param options  The database options, or nil for the default options. */
    public init(name: String, options: DatabaseOptions? = nil) throws {
        if let opts = options {
            let cblOpts = CBLDatabaseOptions()
            cblOpts.directory = opts.directory
            cblOpts.fileProtection = opts.fileProtection
            cblOpts.readOnly = opts.readOnly
            cblOpts.encryptionKey = opts.encryptionKey?.asObject
            _impl = try CBLDatabase(name: name, options: cblOpts)
        } else {
            _impl = try CBLDatabase(name: name)
        }
    }


    /** Closes a database. */
    public func close() throws {
        try _impl.close()
    }


    /** The database's name. */
    public var name: String { return _impl.name }


    /** The database's path. If the database is closed or deleted, nil value will be returned. */
    public var path: String? { return _impl.path }
    
    
    /** Changes the database's encryption key, or removes encryption if the new key is nil.
        @param key  The encryption key in the form of an NSString (a password) or an
        NSData object exactly 32 bytes in length (a raw AES key.) If a string is given,
        it will be internally converted to a raw key using 64,000 rounds of PBKDF2 hashing.
        A nil value will decrypt the database. */
    public func changeEncryptionKey(_ key: EncryptionKey?) throws {
        try _impl.changeEncryptionKey(key?.asObject)
    }


    /** Deletes a database. */
    public func delete() throws {
        try _impl.delete()
    }


    /** Deletes a database of the given name in the given directory. */
    public class func delete(_ name: String, inDirectory directory: String? = nil) throws {
        try CBLDatabase.delete(name, inDirectory: directory)
    }


    /** Checks whether a database of the given name exists in the given directory or not. */
    public class func databaseExists(_ name: String, inDirectory directory: String? = nil) -> Bool {
        return CBLDatabase.databaseExists(name, inDirectory: directory)
    }


    /** Runs a group of database operations in a batch. Use this when performing bulk write operations
        like multiple inserts/updates; it saves the overhead of multiple database commits, greatly
        improving performance. */
    public func inBatch(_ block: () -> Void ) throws {
        try _impl.inBatch(do: block)
    }


    /** Creates a new Document object with no properties and a new (random) UUID.
        The document will be saved to the database when you call -save: on it. */
    public func document() -> Document {
        return Document(_impl.document(), inDatabase: self)
    }


    /** Gets or creates a Document object with the given ID.
        The existence of the Document in the database can be checked by checking its .exists.
        Documents are cached, so there will never be more than one instance in this Database
        object at a time with the same documentID. */
    public func document(withID docID: String) -> Document {
        return Document(_impl.document(withID: docID), inDatabase: self)
    }


    /** Same as document(withID:) */
    public subscript(docID: String) -> Document {
        return self.document(withID: docID)
    }


    /** Checks whether the document of the given ID exists in the database or not. */
    public func contains(_ docID: String) -> Bool {
        return _impl.documentExists(docID)
    }

    /** The conflict resolver for this database.
        If nil, a default algorithm will be used, where the revision with more history wins.
        An individual document can override this for itself by setting its own property. */
    public var conflictResolver: ConflictResolver?


/*
    /** Enumerates all documents in the database, ordered by document ID. */
    public func allDocuments() -> NSEnumerator


    /** Compiles a database query, from any of several input formats.
        Once compiled, the query can be run many times with different parameter values.
        The rows will be sorted by ascending document ID, and no custom values are returned.
        @param where  The query specification. This can be an NSPredicate, or an NSString (interpreted
        as an NSPredicate format string), or nil to return all documents.
        @return  The Query. */
    public func createQueryWhere(_ where: Any?) -> Query
*/


    /** Creates a value index (type kValueIndex) on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
     or NSStrings that are expression format strings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Any]) throws {
        try _impl.createIndex(on: expressions)
    }


    /** Creates an index on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
     or NSStrings that are expression format strings.
     @param type  Type of index to create (value, full-text or geospatial.)
     @param options  Options affecting the index, or NULL for default settings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Any], options: IndexOptions) throws {
        var cblType: CBLIndexType
        var cblOptions = CBLIndexOptions()
        var language: String?
        switch(options) {
            case .valueIndex:
                cblType = CBLIndexType.valueIndex
            case .fullTextIndex(let lang, let ignoreDiacritics):
                cblType = CBLIndexType.fullTextIndex
                language = lang
                cblOptions.ignoreDiacritics = ObjCBool(ignoreDiacritics)
            case .geoIndex:
                cblType = CBLIndexType.geoIndex
        }

        if let language = language {
            try language.withCString({ (cLanguage: UnsafePointer<Int8>) in
                cblOptions.language = cLanguage
                try _impl.createIndex(on: expressions, type: cblType, options: &cblOptions)
            })
        } else {
            try _impl.createIndex(on: expressions, type: cblType, options: &cblOptions)
        }
    }

    
    /** Deletes an existing index. Returns NO if the index did not exist.
     @param expressions  Expressions indexed (same parameter given to -createIndexOn:.)
     @param type  Type of index.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True if the index existed and was deleted, false if it did not exist. */
    public func deleteIndex(on expressions: [Any], type: IndexType) throws {
        try deleteIndex(on: expressions, type: type)
    }


    private let _impl : CBLDatabase
}
