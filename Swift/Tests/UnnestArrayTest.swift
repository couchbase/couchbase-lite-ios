//
//  UnnestArrayTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import CouchbaseLiteSwift

/// Test Spec v1.0.1:
/// https://github.com/couchbaselabs/couchbase-lite-api/blob/master/spec/tests/T0004-Unnest-Array-Index.md

class UnnestArrayTest: CBLTestCase {
    /// 1. TestArrayIndexConfigInvalidExpressions
    /// Description
    ///     Test that creating an ArrayIndexConfiguration with invalid expressions which are an empty expressions or contain null.
    /// Steps
    ///     1. Create a ArrayIndexConfiguration object.
    ///         - path: "contacts"
    ///         - expressions: []
    ///     2. Check that an invalid arument exception is thrown.
    func testArrayIndexConfigInvalidExpressions() throws {
        expectException(exception: .invalidArgumentException) {
            _ = ArrayIndexConfiguration(path: "contacts", expressions: [])
        }
        
        expectException(exception: .invalidArgumentException) {
            _ = ArrayIndexConfiguration(path: "contacts", expressions: [""])
        }
    }
    
    /// 2. TestCreateArrayIndexWithPath
    /// Description
    ///     Test that creating an ArrayIndexConfiguration with invalid expressions which are an empty expressions or contain null.
    /// Steps
    ///     1. Load profiles.json into the collection named "_default.profiles".
    ///     2. Create a ArrayIndexConfiguration object.
    ///         - path: "contacts"
    ///         - expressions: null
    ///     3. Create an array index named "contacts" in the profiles collection.
    ///     4. Get index names from the profiles collection and check that the index named "contacts" exists.
    ///     5. Get info of the index named "contacts" using an internal API and check that the index has path and expressions as configured.
    func testCreateArrayIndexWithPath() throws {
        let profiles = try db.createCollection(name: "profiles")
        try loadJSONResource("profiles_100", collection: profiles)
        let config = ArrayIndexConfiguration(path: "contacts")
        try profiles.createIndex(withName: "contacts", config: config)
        let indexes = try profiles.indexesInfo()
        XCTAssertEqual(indexes!.count, 1)
        XCTAssertEqual(indexes![0]["expr"] as! String, "")
    }
    
    /// 3. TestCreateArrayIndexWithPathAndExpressions
    /// Description
    ///     Test that creating an array index with path and expressions works as expected.
    /// Steps
    ///     1. Load profiles.json into the collection named "_default.profiles".
    ///     2. Create a ArrayIndexConfiguration object.
    ///         - path: "contacts"
    ///         - expressions: ["address.city", "address.state"]
    ///     3. Create an array index named "contacts" in the profiles collection.
    ///     4. Get index names from the profiles collection and check that the index named "contacts" exists.
    ///     5. Get info of the index named "contacts" using an internal API and check that the index has path and expressions as configured.
    func testCreateArrayIndexWithPathAndExpressions() throws {
        let profiles = try db.createCollection(name: "profiles")
        try loadJSONResource("profiles_100", collection: profiles)
        let config = ArrayIndexConfiguration(path: "contacts",expressions: ["address.city", "address.state"])
        try profiles.createIndex(withName: "contacts", config: config)
        let indexes = try profiles.indexesInfo()
        XCTAssertEqual(indexes!.count, 1)
        XCTAssertEqual(indexes![0]["expr"] as! String, "address.city,address.state")
    }
}
