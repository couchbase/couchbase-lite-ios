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
public struct DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public var directory: String = CBLDatabaseConfiguration().directory {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The conflict resolver for this database.
    public var conflictResolver: ConflictResolver = DefaultConflictResolver() {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// The key to encrypt the database with.
    public var encryptionKey: EncryptionKey? {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// Initializes a DatabaseConfiguration's builder with default values.
    public init() {
        self.init(withConfig: nil, readonly: false)
    }
    
    /// Initializes a DatabaseConfiguration's builder with the configuration object.
    public init(withConfig config: DatabaseConfiguration?) {
        self.init(withConfig: config, readonly: false)
    }
    
    // MARK: Internal
    
    private let readonly: Bool
    
    init(withConfig config: DatabaseConfiguration?, readonly: Bool) {
        if let c = config {
            self.directory = c.directory
            self.conflictResolver = c.conflictResolver
            self.encryptionKey = c.encryptionKey
        }
        self.readonly = readonly
    }
    
    func checkReadOnly() {
        if self.readonly {
            fatalError("This configuration object is readonly.")
        }
    }
    
    func toImpl() -> CBLDatabaseConfiguration {
        let config = CBLDatabaseConfiguration()
        config.directory = self.directory
        if !(self.conflictResolver is DefaultConflictResolver) {
            config.conflictResolver =
                BridgingConflictResolver(resolver: self.conflictResolver)
        }
        config.encryptionKey = self.encryptionKey?.impl
        return config
    }
    
}
