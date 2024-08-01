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


/// Configuration for opening a database.
public struct DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public var directory: String = CBLDatabaseConfiguration().directory
    
    /// As Couchbase Lite normally configures its databases, There is a very
    /// small (though non-zero) chance that a power failure at just the wrong
    /// time could cause the most recently committed transaction's changes to
    /// be lost. This would cause the database to appear as it did immediately
    /// before that transaction.
    ///
    /// Setting this mode true ensures that an operating system crash or
    /// power failure will not cause the loss of any data.  FULL synchronous
    /// is very safe but it is also dramatically slower.
    public var isFullSync: Bool = defaultFullSync
    
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
            self.isFullSync = c.isFullSync
            #if COUCHBASE_ENTERPRISE
            self.encryptionKey = c.encryptionKey
            #endif
        }
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLDatabaseConfiguration {
        let config = CBLDatabaseConfiguration()
        config.directory = self.directory
        config.isFullSync = self.isFullSync
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey = self.encryptionKey?.impl
        #endif
        return config
    }
}
