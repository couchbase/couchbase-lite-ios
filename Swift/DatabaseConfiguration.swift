//
//  DatabaseConfiguration.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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


/// Configuration for opening a database.
public struct DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public var directory: String = CBLDatabaseConfiguration().directory
    
    /// As Couchbase Lite normally configures its databases, there is a very
    /// small (though non-zero) chance that a power failure at just the wrong
    /// time could cause the most recently committed transaction's changes to
    /// be lost. This would cause the database to appear as it did immediately
    /// before that transaction.
    ///
    /// Setting this mode true ensures that an operating system crash or
    /// power failure will not cause the loss of any data. FULL synchronous
    /// is very safe but it is also dramatically slower.
    public var fullSync: Bool = defaultFullSync
    
    /// Enables or disables memory-mapped I/O. By default, memory-mapped I/O is enabled.
    /// Disabling it may affect database performance. Typically, there is no need to modify this setting.
    /// - Note: Memory-mapped I/O is always disabled to prevent database corruption on macOS.
    ///         As a result, setting this configuration has no effect on the macOS platform.
    public var mmapEnabled: Bool = defaultMmapEnabled;
    
    #if COUCHBASE_ENTERPRISE
    /// The key to encrypt the database with.
    public var encryptionKey: EncryptionKey?
    #endif
    
    /// Initializes a DatabaseConfiguration's builder with default values.
    public init() {
        self.init(config: nil)
    }
    
    /// Initializes a DatabaseConfiguration's builder with the configuration object.
    public init(config: DatabaseConfiguration?) {
        if let c = config {
            self.directory = c.directory
            self.fullSync = c.fullSync
            self.mmapEnabled = c.mmapEnabled
            
            #if COUCHBASE_ENTERPRISE
            self.encryptionKey = c.encryptionKey
            #endif
        }
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLDatabaseConfiguration {
        let config = CBLDatabaseConfiguration()
        config.directory = self.directory
        config.fullSync = self.fullSync
        config.mmapEnabled = self.mmapEnabled
        
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey = self.encryptionKey?.impl
        #endif
        
        return config
    }
}
