//
//  CBLTestCase.swift
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

import XCTest
import Foundation
import CouchbaseLiteSwift


class CBLTestCase: XCTestCase {

    var db: Database!

    let databaseName = "testdb"
    
    #if COUCHBASE_ENTERPRISE
        let directory = NSTemporaryDirectory().appending("CouchbaseLite-EE")
    #else
        let directory = NSTemporaryDirectory().appending("CouchbaseLite")
    #endif
    
    override func setUp() {
        super.setUp()
        
        if FileManager.default.fileExists(atPath: self.directory) {
            try! FileManager.default.removeItem(atPath: self.directory)
        }
        try! openDB()
    }
    
    
    override func tearDown() {
        try! db.close()
        super.tearDown()
    }
    
    
    func openDB(name: String) throws -> Database {
        let config = DatabaseConfiguration()
        config.directory = self.directory
        return try Database(name: name, config: config)
    }
    
    
    func openDB() throws {
        db = try openDB(name: databaseName)
    }

    
    func reopenDB() throws {
        try db.close()
        db = nil
        try openDB()
    }
    
    
    func cleanDB() throws {
        try db.delete()
        try reopenDB()
    }
    
    
    func createDocument() -> MutableDocument {
        return MutableDocument()
    }
    
    
    func createDocument(_ id: String?) -> MutableDocument {
        return MutableDocument(id: id)
    }
    
    
    func createDocument(_ id: String?, data: [String:Any]) -> MutableDocument {
        return MutableDocument(id: id, data: data)
    }
    
    
    func saveDocument(_ document: MutableDocument) throws {
        try db.saveDocument(document)
        let savedDoc = db.document(withID: document.id)
        XCTAssertNotNil(savedDoc)
        XCTAssertEqual(savedDoc!.id, document.id)
        XCTAssertTrue(savedDoc!.toDictionary() == document.toDictionary())
    }
    
    
    func saveDocument(_ document: MutableDocument, eval: (Document) -> Void) throws {
        eval(document)
        try saveDocument(document)
        eval(document)
        let savedDoc = db.document(withID: document.id)!
        eval(savedDoc)
    }
    
    
    func dataFromResource(name: String, ofType: String) throws -> NSData {
        let res = ("Support" as NSString).appendingPathComponent(name)
        let path = Bundle(for: type(of:self)).path(forResource: res, ofType: ofType)
        return try! NSData(contentsOfFile: path!, options: [])
    }

    
    func stringFromResource(name: String, ofType: String) throws -> String {
        let res = ("Support" as NSString).appendingPathComponent(name)
        let path = Bundle(for: type(of:self)).path(forResource: res, ofType: ofType)
        return try String(contentsOfFile: path!, encoding: String.Encoding.utf8)
    }

    
    func loadJSONResource(name: String) throws {
        try autoreleasepool {
            let contents = try stringFromResource(name: name, ofType: "json")
            var n = 0
            try db.inBatch {
                contents.enumerateLines(invoking: { (line: String, stop: inout Bool) in
                    n += 1
                    let json = line.data(using: String.Encoding.utf8, allowLossyConversion: false)
                    let dict = try! JSONSerialization.jsonObject(with: json!, options: []) as! [String:Any]
                    let docID = String(format: "doc-%03llu", n)
                    let doc = MutableDocument(id: docID, data: dict)
                    try! self.db.saveDocument(doc)
                })
            }
        }
    }
    
    
    func jsonFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = NSTimeZone(abbreviation: "UTC")! as TimeZone
        return formatter.string(from: date).appending("Z")
    }
    
    
    func dateFromJson(_ date: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter.timeZone = NSTimeZone.local
        return formatter.date(from: date)!
    }
    
    
    func expectError(domain: String, code: Int, block: @escaping () throws -> Void) {
        CBLTestHelper.allowException {
            var error: NSError?
            do {
                try block()
            }
            catch let e as NSError {
                error = e
            }
            
            XCTAssertNotNil(error, "Block expected to fail but didn't")
            XCTAssertEqual(error?.domain, domain)
            XCTAssertEqual(error?.code, code)
        }
    }
}

/** Comparing JSON Dictionary */
public func ==(lhs: [String: Any], rhs: [String: Any] ) -> Bool {
    return NSDictionary(dictionary: lhs).isEqual(to: rhs)
}

/** Comparing JSON Array */
public func ==(lhs: [Any], rhs: [Any] ) -> Bool {
    return NSArray(array: lhs).isEqual(to: rhs)
}
