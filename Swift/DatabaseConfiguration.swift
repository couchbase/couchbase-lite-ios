//
//  DatabaseConfiguration.swift
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


/// Configuration for opening a database.
public struct DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public var directory: String = CBLDatabaseConfiguration().directory
    
    ///  Experiment API. Enable version vector.
    
    /// If the enableVersionVector is set to true, the database will use version vector instead of
    /// using revision tree. When enabling version vector on an existing database, the database
    /// will be upgraded to use the revision tree while the database is opened.
    ///
    /// NOTE:
    /// 1. The database that uses version vector cannot be downgraded back to use revision tree.
    /// 2. The current version of Sync Gateway doesn't support version vector so the syncronization
    /// with Sync Gateway will not be working.
    public var enableVersionVector: Bool = false
    
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
            self.enableVersionVector = c.enableVersionVector
            #if COUCHBASE_ENTERPRISE
            self.encryptionKey = c.encryptionKey
            #endif
        }
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLDatabaseConfiguration {
        let config = CBLDatabaseConfiguration()
        config.directory = self.directory
        config.enableVersionVector = self.enableVersionVector
        #if COUCHBASE_ENTERPRISE
        config.encryptionKey = self.encryptionKey?.impl
        #endif
        return config
    }
    
}
