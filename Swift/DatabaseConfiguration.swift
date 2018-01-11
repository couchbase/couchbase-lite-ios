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
    
    var impl: CBLEncryptionKey {
        switch (self) {
        case .key (let data):
            return CBLEncryptionKey(key: data)
        case .password(let pwd):
            return CBLEncryptionKey(password: pwd)
        }
    }
}


/// Configuration for opening a database.
public final class DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public let directory: String
    
    /// The conflict resolver for this database.
    public let conflictResolver: ConflictResolver
    
    /// The key to encrypt the database with.
    public let encryptionKey: EncryptionKey?
    
    /// The file protection options (iOS only.)
    public let fileProtection: NSData.WritingOptions
    
    /// The builder for the DatabaseConfiguration.
    public final class Builder {
        
        /// Initializes a DatabaseConfiguration's builder with default values.
        public init() { }
        
        
        /// Initializes a DatabaseConfiguration's builder with a configuration.
        ///
        /// - Parameter config: The configuration.
        public init(config: DatabaseConfiguration?) {
            if let c = config {
                self.directory = c.directory
                self.conflictResolver = c.conflictResolver
                self.encryptionKey = c.encryptionKey
                self.fileProtection = c.fileProtection
            }
        }
        
        
        /// Sets path to the directory to store the database in. If the directory
        /// doesn't already exist it will be created when the database is opened.
        /// The default directory, in Application Support.
        ///
        /// - Parameter directory: The directory.
        /// - Returns: The self object.
        @discardableResult public func setDirectory(_ directory: String) -> Self {
            self.directory = directory
            return self
        }
        
        
        /// Sets a custom conflict resolver used for solving the conflicts
        /// when saving or deleting documents in the database. Without setting the
        /// conflict resolver, CouchbaseLite will use the default conflict
        /// resolver.
        ///
        /// - Parameter conflictResolver: The conflict resolver.
        /// - Returns: The self object.
        @discardableResult public func setConflictResolver(_ conflictResolver: ConflictResolver) -> Self {
            self.conflictResolver = conflictResolver
            return self
        }
        
        
        /// Sets a key to encrypt the database with. If the database does not
        /// exist and is being created, it will use this key, and the same key
        /// must be given every time it's opened. A default value is nil, which
        /// means the database is unencrypted.
        ///
        /// - Parameter encryptionKey: The encryption key.
        /// - Returns: The self object.
        @discardableResult public func setEncryptionKey(_ encryptionKey: EncryptionKey?) -> Self {
            self.encryptionKey = encryptionKey
            return self
        }
        
        
        /// Sets file protection options (iOS only.) Defaults to
        /// whatever file protection settings you've specified in your app's
        /// entitlements. Specifying a nonzero value here overrides those settings
        /// for the database files.
        ///
        /// If file protection is at the highest level, NSDataWritingFileProtectionCompleteUnlessOpen
        /// or NSDataWritingFileProtectionComplete, it will not be possible to
        /// read or write the database when the device is locked. This can make
        /// it impossible to run replications in the background or respond to
        /// push notifications.
        ///
        /// - Parameter fileProtection: The file protection options.
        /// - Returns: The self object.
        @discardableResult public func setFileProtection(_ fileProtection: NSData.WritingOptions) -> Self {
            self.fileProtection = fileProtection
            return self
        }
        
        
        /// Builds a database configuration object from the current settings.
        ///
        /// - Returns: The self object.
        public func build() -> DatabaseConfiguration {
            return DatabaseConfiguration(withBuilder: self)
        }
        
        
        // Mark: Internal
        
        var directory = CBLDatabaseConfiguration().directory
        
        var conflictResolver: ConflictResolver = DefaultConflictResolver()
        
        var encryptionKey: EncryptionKey?
        
        var fileProtection: NSData.WritingOptions = []
    }
    
    
    // MARK: Internal
    
    
    init(withBuilder builder: Builder) {
        self.directory = builder.directory
        self.conflictResolver = builder.conflictResolver
        self.encryptionKey = builder.encryptionKey
        self.fileProtection = builder.fileProtection
    }
    
    
    func toImpl() -> CBLDatabaseConfiguration {
        let c = CBLDatabaseConfiguration.init { (builder) in
            builder.directory = self.directory
            if !(self.conflictResolver is DefaultConflictResolver) {
                builder.conflictResolver =
                    BridgingConflictResolver(resolver: self.conflictResolver)
            }
            builder.encryptionKey = self.encryptionKey?.impl
            builder.fileProtection = self.fileProtection
        }
        return c
    }
    
}
