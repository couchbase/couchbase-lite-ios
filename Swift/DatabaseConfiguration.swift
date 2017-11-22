//
//  DatabaseConfiguration.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// The encryption key, a raw AES-256 key data which has exactly 32 bytes in length
/// or a password string. If the password string is given, it will be internally converted to a
/// raw AES key using 64,000 rounds of PBKDF2 hashing.
///
/// - key: 32-byte AES-256 data key. To create a key, generate random data using a secure
///        cryptographic randomizer like SecRandomCopyBytes or CCRandomGenerateBytes.
/// - password: Password string that will be internally converted to a raw AES-256 key
///             using 64,000 rounds of PBKDF2 hashing.
public enum EncryptionKey {
    case key (Data)
    case password (String)
    
    var asObject: CBLEncryptionKey {
        switch (self) {
        case .key (let data):
            return CBLEncryptionKey(key: data)
        case .password(let pwd):
            return CBLEncryptionKey(password: pwd)
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
        get {
            return _directory ?? CBLDatabaseConfiguration().directory
        }
        set {
            _directory = newValue
        }
    }
    
    
    /// The conflict resolver for this replicator. Setting nil means using the default
    /// conflict resolver, where the revision with more history wins.
    public var conflictResolver: ConflictResolver? {
        get {
            return _conflictResolver ?? DefaultConflictResolver()
        }
        set {
            _conflictResolver = newValue
        }
    }
    
    /// A key to encrypt the database with. If the database does not exist and is being created, it
    /// will use this key, and the same key must be given every time it's opened.
    ///
    /// * The primary form of key is a Data object 32 bytes in length: this is interpreted as a raw
    ///   AES-256 key. To create a key, generate random data using a secure cryptographic randomizer
    ///   like SecRandomCopyBytes or CCRandomGenerateBytes.
    /// * Alternatively, the value may be a string containing a password. This will be run through
    ///   64,000 rounds of the PBKDF algorithm to securely convert it into an AES-256 key.
    /// * A default nil value, of course, means the database is unencrypted.
    public var encryptionKey: EncryptionKey?
    
    /// protection
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
    
    var _conflictResolver: ConflictResolver?
    
    func toImpl() -> CBLDatabaseConfiguration {
        let c = CBLDatabaseConfiguration()
        
        if let dir = _directory {
            c.directory = dir
        }
        
        if let r = self.conflictResolver, !(r is DefaultConflictResolver) {
            c.conflictResolver = BridgingConflictResolver(resolver: r)
        }
        
        c.encryptionKey = self.encryptionKey?.asObject
        
        c.fileProtection = self.fileProtection
        
        return c
    }
}
