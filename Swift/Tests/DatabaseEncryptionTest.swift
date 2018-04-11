//
//  DatabaseEncryptionTest.swift
//  CBL Swift
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
import CouchbaseLiteSwift


class DatabaseEncryptionTest: CBLTestCase {
    
    var seekrit: Database?
    
    override func tearDown() {
        if let sk = seekrit {
            try! sk.close()
        }
        super.tearDown()
    }

    func openSeekrit(password: String?) throws -> Database {
        let config = DatabaseConfiguration()
        config.encryptionKey = password != nil ? EncryptionKey.password(password!) : nil
        config.directory = self.directory
        return try Database(name: "seekrit", config: config)
    }
    
    func testUnEncryptedDatabase() throws {
        seekrit = try openSeekrit(password: nil)
        
        let doc = createDocument(nil, data: ["answer": 42])
        try seekrit!.saveDocument(doc)
        try seekrit!.close()
        seekrit = nil
        
        // Try to reopen with password (fails):
        expectError(domain: CBLErrorDomain, code: CBLErrorUnreadableDatabase) {
            try _ = self.openSeekrit(password: "wrong")
        }
        
        // Reopen with no password:
        seekrit = try openSeekrit(password: nil)
        XCTAssertEqual(seekrit!.count, 1)
    }
    
    func testEncryptedDatabase() throws {
        // Create encrypted database:
        seekrit = try openSeekrit(password: "letmein")
        
        let doc = createDocument(nil, data: ["answer": 42])
        try seekrit!.saveDocument(doc)
        try seekrit!.close()
        seekrit = nil
        
        // Reopen without password (fails):
        expectError(domain: CBLErrorDomain, code: CBLErrorUnreadableDatabase) {
            try _ = self.openSeekrit(password: nil)
        }
        
        // Reopen with wrong password (fails):
        expectError(domain: CBLErrorDomain, code: CBLErrorUnreadableDatabase) {
            try _ = self.openSeekrit(password: "wrong")
        }
        
        // Reopen with correct password:
        seekrit = try openSeekrit(password: "letmein")
    }
    
    func testDeleteEcnrypedDatabase() throws {
        // Create encrypted database:
        seekrit = try openSeekrit(password: "letmein")
        
        // Delete database:
        try seekrit!.delete()
        
        // Re-create database:
        seekrit = try openSeekrit(password: nil)
        XCTAssertEqual(seekrit!.count, 0)
        try seekrit!.close()
        seekrit = nil
        
        // Make sure it doesn't need a password now:
        seekrit = try openSeekrit(password: nil)
        XCTAssertEqual(seekrit!.count, 0)
        try seekrit!.close()
        seekrit = nil
        
        // Make sure old password doesn't work:
        expectError(domain: CBLErrorDomain, code: CBLErrorUnreadableDatabase) {
            try _ = self.openSeekrit(password: "letmein")
        }
    }
    
    func testCompactEncryptedDatabase() throws {
        // Create encrypted database:
        seekrit = try openSeekrit(password: "letmein")
        
        // Create a doc and then update it:
        let doc = createDocument(nil, data: ["answer": 42])
        try seekrit!.saveDocument(doc)
        doc.setValue(84, forKey: "answer")
        try seekrit!.saveDocument(doc)
        
        // Compact:
        try seekrit!.compact()
        
        // Update the document again:
        doc.setValue(85, forKey: "answer")
        try seekrit!.saveDocument(doc)
        
        // Close and re-open:
        try seekrit!.close()
        seekrit = try openSeekrit(password: "letmein")
        XCTAssertEqual(seekrit!.count, 1)
    }
    
    func testEncryptedBlobs() throws {
        try _testEncryptedBlobsWithPassword(password: "letmein")
    }
    
    func _testEncryptedBlobsWithPassword(password: String?) throws {
        // Create database with the password:
        seekrit = try openSeekrit(password: password)
        
        // Save a doc with a blob:
        let doc = createDocument("att")
        let body = "This is a blob!".data(using: .utf8)!
        var blob = Blob(contentType: "text/plain", data: body)
        doc.setValue(blob, forKey: "blob")
        try seekrit!.saveDocument(doc)
        
        // Read content from the raw blob file:
        blob = doc.blob(forKey: "blob")!
        let digest = blob.digest
        XCTAssertNotNil(digest)
        
        let index = digest!.index(digest!.startIndex, offsetBy: 5)
        let fileName = digest!.substring(from: index).replacingOccurrences(of: "/", with: "_")
        let path = "\(seekrit!.path!)Attachments/\(fileName).blob"
        let raw = FileHandle(forReadingAtPath: path)!.readDataToEndOfFile()
        if password != nil {
            XCTAssertNotEqual(raw, body)
        } else {
            XCTAssertEqual(raw, body)
        }
        
        // Check blob content:
        let savedDoc = seekrit!.document(withID: "att")!
        XCTAssertNotNil(savedDoc)
        blob = savedDoc.blob(forKey: "blob")!
        XCTAssertNotNil(blob.digest)
        XCTAssertNotNil(blob.content)
        let content = String.init(data: blob.content!, encoding: .utf8)
        XCTAssertEqual(content, "This is a blob!")
    }
    
    func testMultipleDatabases() throws {
        // Create encrypted database:
        seekrit = try openSeekrit(password: "seekrit")
        
        // Get another instance of the database:
        let seekrit2 = try openSeekrit(password: "seekrit")
        try seekrit2.close()
        
        // Try rekey:
        let newKey = EncryptionKey.password("foobar")
        try seekrit!.setEncryptionKey(newKey)
    }
    
    func rekey(oldPassword: String?, newPassword: String?) throws {
        // First run the encryped blobs test to populate the database:
        try _testEncryptedBlobsWithPassword(password: oldPassword)
        
        // Create some documents:
        try seekrit!.inBatch {
            for i in 0...99 {
                let doc = createDocument(nil, data: ["seq": i])
                try seekrit!.saveDocument(doc)
            }
        }
        
        // Rekey:
        let newKey = newPassword != nil ? EncryptionKey.password(newPassword!) : nil
        try seekrit!.setEncryptionKey(newKey)
        
        // Close & reopen seekrit:
        try seekrit!.close()
        seekrit = nil
        
        // Reopen the database with the new key:
        let seekrit2 = try openSeekrit(password: newPassword)
        seekrit = seekrit2
        
        // Check the document and its attachment
        let doc = seekrit!.document(withID: "att")!
        XCTAssertNotNil(doc)
        let blob = doc.blob(forKey: "blob")!
        XCTAssertNotNil(blob.digest)
        XCTAssertNotNil(blob.content)
        let content = String.init(data: blob.content!, encoding: .utf8)
        XCTAssertEqual(content, "This is a blob!")
        
        // Query documents:
        let seq = Expression.property("seq")
        let query = QueryBuilder
            .select(SelectResult.expression(seq))
            .from(DataSource.database(seekrit!))
            .where(seq.notNullOrMissing())
            .orderBy(Ordering.expression(seq))
        let rs = try query.execute()
        XCTAssertEqual(Array(rs).count, 100)
        
        var i = 0;
        for r in rs {
            XCTAssertEqual(r.int(at: 0), i)
            i = i + 1
        }
    }
    
}
