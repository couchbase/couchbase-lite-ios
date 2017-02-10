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

    let kDatabaseName = "testdb"

    let kDirectory = NSTemporaryDirectory().appending("/CouchbaseLite")

    override func setUp() {
        super.setUp()

        try! Database.delete(kDatabaseName, inDirectory: kDirectory)
        try! openDB()
    }
    
    override func tearDown() {
        try! db.close()
        super.tearDown()
    }


    func openDB() throws {
        var options = DatabaseOptions()
        options.directory = kDirectory
        db = try Database(name: kDatabaseName, options: options)
    }

    func reopenDB() throws {
        try db.close()
        db = nil
        try openDB()
    }

    func dataFromResource(name: String, ofType: String) throws -> NSData {
        let path = Bundle(for: type(of:self)).path(forResource: name, ofType: ofType)
        return try! NSData(contentsOfFile: path!, options: [])
    }

    func stringFromResource(name: String, ofType: String) throws -> String {
        let path = Bundle(for: type(of:self)).path(forResource: name, ofType: ofType)
        return try String(contentsOfFile: path!, encoding: String.Encoding.utf8)
    }

    func loadJSONResource(resourceName: String) throws {
        try autoreleasepool {
            let contents = try stringFromResource(name: resourceName, ofType: "json")
            var n = 0
            try db.inBatch {
                contents.enumerateLines(invoking: { (line: String, stop: inout Bool) in
                    n += 1
                    let json = line.data(using: String.Encoding.utf8, allowLossyConversion: false)
                    let properties = try! JSONSerialization.jsonObject(with: json!, options: []) as! [String:Any]

                    let docID = String(format: "doc-%03llu", n)
                    let doc = self.db[docID]
                    doc.properties = properties
                    try! doc.save()
                })
            }
        }
    }

}
