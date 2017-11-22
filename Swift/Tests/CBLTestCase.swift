//
//  CBLTestCase.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import XCTest
import Foundation
import CouchbaseLiteSwift


class CBLTestCase: XCTestCase {

    var db: Database!
    
    var conflictResolver: ConflictResolver?

    let databaseName = "testdb"
    
    let directory = NSTemporaryDirectory().appending("CouchbaseLite")

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
        var config = DatabaseConfiguration()
        config.directory = directory
        config.conflictResolver = conflictResolver
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
    
    
    func createDocument() -> MutableDocument {
        return MutableDocument()
    }
    
    
    func createDocument(_ id: String?) -> MutableDocument {
        return MutableDocument(withID: id)
    }
    
    
    func createDocument(_ id: String?, dictionary: [String:Any]) -> MutableDocument {
        return MutableDocument(withID: id, dictionary: dictionary)
    }
    
    
    @discardableResult func saveDocument(_ document: MutableDocument) throws -> Document {
        return try db.saveDocument(document)
    }
    
    
    @discardableResult func saveDocument(_ document: MutableDocument, eval: (Document) -> Void) throws -> Document {
        eval(document)
        let doc = try saveDocument(document)
        eval(doc)
        return doc
    }
    
    
    func dataFromResource(name: String, ofType: String) throws -> NSData {
        let path = Bundle(for: type(of:self)).path(forResource: name, ofType: ofType)
        return try! NSData(contentsOfFile: path!, options: [])
    }

    
    func stringFromResource(name: String, ofType: String) throws -> String {
        let path = Bundle(for: type(of:self)).path(forResource: name, ofType: ofType)
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
                    let doc = MutableDocument(withID: docID, dictionary: dict)
                    try! self.db.saveDocument(doc)
                })
            }
        }
    }
    
    
    func jsonFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = NSTimeZone(abbreviation: "UTC")! as TimeZone!
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
