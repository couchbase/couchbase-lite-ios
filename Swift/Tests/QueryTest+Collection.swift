//
//  QueryTest+Collection.swift
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

import XCTest
import CouchbaseLiteSwift

class QueryTest_Collection: QueryTest {
    override func setUpWithError() throws {
        try super.setUpWithError()
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
    }
    
    // MARK: 8.11 SQL++ Query
    
    func testQueryDefaultCollection() throws {
        try testQueryCollection(self.db.defaultCollection(), queries: [
            "SELECT name.first FROM _ ORDER BY name.first LIMIT 1",
            "SELECT name.first FROM _default ORDER BY name.first limit 1",
            "SELECT name.first FROM testdb ORDER BY name.first limit 1"
        ])
    }
    
    func testQueryDefaultScope() throws {
        let col = try self.db.createCollection(name: "names")
        
        try testQueryCollection(col, queries: [
            "SELECT name.first FROM _default.names ORDER BY name.first LIMIT 1",
            "SELECT name.first FROM names ORDER BY name.first LIMIT 1"
        ])
    }
    
    func testQueryCollection() throws {
        let col = try self.db.createCollection(name: "names", scope: "people")
        
        try testQueryCollection(col,queries: [
            "SELECT name.first FROM people.names ORDER BY name.first LIMIT 1"
        ])
    }
    
    func testQueryInvalidCollection() throws {
        let col = try self.db.createCollection(name: "names", scope: "people")
        
        try loadJSONResource("names_100", collection: col)
        
        expectError(domain: CBLErrorDomain, code: CBLError.invalidQuery) {
            let _ = try self.db.createQuery("SELECT name.first FROM person.names ORDER BY name.first LIMIT 1")
        }
    }
    
    func testJoinWithCollections() throws {
        let flowersCol = try self.db.createCollection(name: "flowers", scope: "test")
        let colorsCol = try self.db.createCollection(name: "colors", scope: "test")
        
        try flowersCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "name": "rose"]))
        try flowersCol.save(document: MutableDocument(id: "c2", data: ["cid": "c2", "name": "hydrangea"]))
        
        try colorsCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "color": "red"]))
        try colorsCol.save(document: MutableDocument(id: "c2", data: ["cid": "c2", "color": "blue"]))
        try colorsCol.save(document: MutableDocument(id: "c3", data: ["cid": "c3", "color": "white"]))
        
        let qStr = "SELECT a.name, b.color FROM test.flowers a JOIN test.colors b ON a.cid = b.cid ORDER BY a.name"
        let q = try self.db.createQuery(qStr)
        let rs = try q.execute()
        let results = rs.allResults()
        
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].string(forKey: "name"), "hydrangea")
        XCTAssertEqual(results[0].string(forKey: "color"), "blue")
        XCTAssertEqual(results[1].string(forKey: "name"), "rose")
        XCTAssertEqual(results[1].string(forKey: "color"), "red")
    }
    
    func testQueryBuilderWithDefaultCollectionAsDataSource() throws {
        let col = try self.db.defaultCollection();
        
        try loadJSONResource("names_100", collection: self.db.defaultCollection())
        
        let q = QueryBuilder
            .select([SelectResult.property("name.first")])
            .from(DataSource.collection(col))
            .orderBy([Ordering.property("name.first").ascending()])
            .limit(Expression.int(1))
        
        let rs = try q.execute()
        let results = rs.allResults()
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.string(forKey: "first"), "Abe")
    }
    
    func testQueryBuilderWithCollectionAsDataSource() throws {
        let col = try self.db.createCollection(name: "names", scope: "people")
        
        try loadJSONResource("names_100", collection: col)
        
        let q = QueryBuilder
            .select([SelectResult.property("name.first")])
            .from(DataSource.collection(col))
            .orderBy([Ordering.property("name.first").ascending()])
            .limit(Expression.int(1))
        
        let rs = try q.execute()
        let results = rs.allResults()
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.string(forKey: "first"), "Abe")
    }
    
    func testSelectAllResultKey() throws {
        let flowersCol = try self.db.createCollection(name: "flowers", scope: "test")
        let defaultCol = try self.db.defaultCollection();
        
        try flowersCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "name": "rose"]))
        try defaultCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "name": "rose"]))
        
        let froms = [
            db.name,
            "_",
            "_default._default",
            "test.flowers",
            "test.flowers as f"
        ];
        
        let expectedKeyNames = [
            db.name,
            "_",
            "_default",
            "flowers",
            "f"
        ];
        
        var i = 0;
        for from in froms {
            let query = try self.db.createQuery("SELECT * FROM \(from)")
            let results = try query.execute().allResults()
            XCTAssertEqual(results.count, 1)
            XCTAssertNotNil(results.first?.dictionary(forKey: expectedKeyNames[i]))
            i = i + 1;
        }
    }
    
    func testQueryBuilderSelectAllResultKey() throws {
        let flowersCol = try self.db.createCollection(name: "flowers", scope: "test")
        let defaultCol = try self.db.defaultCollection();
        
        try flowersCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "name": "rose"]))
        try defaultCol.save(document: MutableDocument(id: "c1", data: ["cid": "c1", "name": "rose"]))
        
        let froms = [
            DataSource.collection(defaultCol),
            DataSource.collection(flowersCol),
            DataSource.collection(flowersCol).as("f")
        ];
        
        let expectedKeyNames = [
            "_default",
            "flowers",
            "f"
        ];
        
        var i = 0;
        for from in froms {
            let query = QueryBuilder.select(SelectResult.all()).from(from);
            let results = try query.execute().allResults()
            XCTAssertEqual(results.count, 1)
            XCTAssertNotNil(results.first?.dictionary(forKey: expectedKeyNames[i]))
            i = i + 1;
        }
    }
    
    // MARK: helper method
    
    func testQueryCollection(_ collection: Collection, queries: [String]) throws {
        try loadJSONResource("names_100", collection: collection)
        
        for query in queries {
            let q = try self.db.createQuery(query)
            let rs = try q.execute()
            let results = rs.allResults()
            
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.string(forKey: "first"), "Abe")
        }
    }
}
