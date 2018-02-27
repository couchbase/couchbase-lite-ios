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
public class DatabaseConfiguration {
    
    /// Path to the directory to store the database in.
    public var directory: String = CBLDatabaseConfiguration().directory {
        willSet(newValue) {
            checkReadOnly()
        }
    }
    
    /// Initializes a DatabaseConfiguration's builder with default values.
    public convenience init() {
        self.init(config: nil, readonly: false)
    }
    
    /// Initializes a DatabaseConfiguration's builder with the configuration object.
    public convenience init(config: DatabaseConfiguration?) {
        self.init(config: config, readonly: false)
    }
    
    // MARK: Internal
    
    private let readonly: Bool
    
    init(config: DatabaseConfiguration?, readonly: Bool) {
        if let c = config {
            self.directory = c.directory
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
        return config
    }

}
