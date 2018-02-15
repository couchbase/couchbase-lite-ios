//
//  SampleCodeTest.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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


class SampleCodeTest: CBLTestCase {
    
    var database: Database!
    
    var replicator: Replicator!
    
    // MARK: Database
    
    func dontTestNewDatabase() throws {
        // <doc>
        do {
            self.database = try Database(name: "my-database")
        } catch {
            print(error)
        }
        // </doc>
    }
    
    #if COUCHBASE_ENTERPRISE
    func dontTestEncryption() throws {
        // <doc>
        let config = DatabaseConfiguration()
        config.encryptionKey = EncryptionKey.password("secretpassword")
        self.database = try Database(name: "my-database", config: config)
        // </doc>
    }
    #endif
    
    func dontTestLogging() throws {
        // <doc>
        Database.setLogLevel(.verbose, domain: .replicator)
        Database.setLogLevel(.verbose, domain: .query)
        // </doc>
    }
    
    func dontTestLoadingPrebuilt() throws {
        // <doc>
        let path = Bundle.main.path(forResource: "travel-sample", ofType: "cblite2")!
        if !Database.exists(withName: "travel-sample") {
            do {
                try Database.copy(fromPath: path, toDatabase: "travel-sample", withConfig: nil)
            } catch {
                fatalError("Could not load pre-built database")
            }
        }
        // </doc>
    }
    
    // MARK: Document
    
    func dontTestInitializer() throws {
        database = self.db
        
        // <doc>
        let newTask = MutableDocument()
            .setString("task", forKey: "type")
            .setString("todo", forKey: "owner")
            .setDate(Date(), forKey: "createdAt")
        try database.saveDocument(newTask)
        // </doc>
    }
    
    func dontTestMutability() throws {
        database = self.db
        
        // <doc>
        guard let document = database.document(withID: "xyz") else { return }
        let mutableDocument = document.toMutable()
        mutableDocument.setString("apples", forKey: "name")
        try database.saveDocument(mutableDocument)
        // </doc>
    }
    
    func dontTestTypedAcessors() throws {
        let newTask = MutableDocument()
        
        // <doc>
        newTask.setValue(Date(), forKey: "createdAt")
        let date = newTask.date(forKey: "createdAt")
        // </doc>
        
        print("\(date!)")
    }
    
    func dontTestBatchOperations() throws {
        // <doc>
        do {
            try database.inBatch {
                for i in 0...10 {
                    let doc = MutableDocument()
                    doc.setValue("user", forKey: "type")
                    doc.setValue("user \(i)", forKey: "name")
                    doc.setBoolean(false, forKey: "admin")
                    try database.saveDocument(doc)
                    print("saved user document \(doc.string(forKey: "name")!)")
                }
            }
        } catch let error {
            print(error.localizedDescription)
        }
        // </doc>
    }
    
    func dontTestBlob() throws {
    #if TARGET_OS_IPHONE
        database = self.db
        let newTask = MutableDocument()
        var image: UIImage!
        
        // <doc>
        let appleImage = UIImage(named: "avatar.jpg")!
        let imageData = UIImageJPEGRepresentation(appleImage, 1)!
        
        let blob = Blob(contentType: "image/jpeg", data: imageData)
        newTask.setBlob(blob, forKey: "avatar")
        try database.saveDocument(newTask)
        
        if let taskBlob = newTask.blob(forKey: "image") {
            image = UIImage(data: taskBlob.content!)
        }
        // </doc>
        
        print("\(image)")
    #endif
    }
    
    // MARK: Query
    
    func dontTestIndexing() throws {
        database = self.db
        
        // <doc>
        let index = IndexBuilder.valueIndex(items:
            ValueIndexItem.expression(Expression.property("type")),
            ValueIndexItem.expression(Expression.property("name")))
        try database.createIndex(index, withName: "TypeNameIndex")
        // </doc>
    }
    
    func dontTestSelect() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("type"),
                SelectResult.property("name")
            )
            .from(DataSource.database(database))

        do {
            for result in try query.execute() {
                print("document id :: \(result.string(forKey: "id")!)")
                print("document name :: \(result.string(forKey: "name")!)")
            }
        } catch {
            print(error)
        }
        // </doc>
    }
    
    func dontTestSelectAll() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(SelectResult.all())
            .from(DataSource.database(database))
        // </doc>
        
        print("\(query)")
    }
    
    func dontTestWhere() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(SelectResult.all())
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("hotel")))
            .limit(Expression.int(10))
        
        do {
            for result in try query.execute() {
                if let dict = result.dictionary(forKey: "travel-sample") {
                    print("document name :: \(dict.string(forKey: "name")!)")
                }
            }
        } catch {
            print(error)
        }
        // </doc>
    }
    
    func dontTestCollectionOperator() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("name"),
                SelectResult.property("public_likes")
            )
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("hotel"))
                .and(ArrayFunction.contains(Expression.property("public_likes"), value: Expression.string("Armani Langworth")))
        )
        
        do {
             for result in try query.execute() {
                print("public_likes :: \(result.array(forKey: "public_likes")!.toArray())")
            }
        }
        // </doc>
    }
    
    func dontTestLikeOperator() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("country"),
                SelectResult.property("name")
            )
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("landmark"))
                .and( Expression.property("name").like(Expression.string("Royal engineers museum")))
            )
            .limit(Expression.int(10))
        
        do {
            for result in try query.execute() {
                print("name property :: \(result.string(forKey: "name")!)")
            }
        }
        // </doc>
    }
    
    func dontTestWildCardMatch() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("country"),
                SelectResult.property("name")
            )
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("landmark"))
                .and(Expression.property("name").like(Expression.string("eng%e%")))
            )
            .limit(Expression.int(10))
        // </doc>
        
        do {
            for result in try query.execute() {
                print("name property :: \(result.string(forKey: "name")!)")
            }
        }
    }
    
    func dontTestWildCardCharacterMatch() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("country"),
                SelectResult.property("name")
            )
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("landmark"))
                .and(Expression.property("name").like(Expression.string("eng____r")))
            )
            .limit(Expression.int(10))
        // </doc>
        
        do {
            for result in try query.execute() {
                print("name property :: \(result.string(forKey: "name")!)")
            }
        }
    }
    
    func dontTestRegexMatch() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("name")
            )
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("landmark"))
                .and(Expression.property("name").like(Expression.string("\\bEng.*e\\b")))
            )
            .limit(Expression.int(10))
        // </doc>
        
        do {
            for result in try query.execute() {
                print("name property :: \(result.string(forKey: "name")!)")
            }
        }
    }
    
    func dontTestJoin() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Expression.property("name").from("airline")),
                SelectResult.expression(Expression.property("callsign").from("airline")),
                SelectResult.expression(Expression.property("destinationairport").from("route")),
                SelectResult.expression(Expression.property("stops").from("route")),
                SelectResult.expression(Expression.property("airline").from("route"))
            )
            .from(
                DataSource.database(database!).as("airline")
            )
            .join(
                Join.join(DataSource.database(database!).as("route"))
                    .on(
                        Meta.id.from("airline")
                            .equalTo(Expression.property("airlineid").from("route"))
                )
            )
            .where(
                Expression.property("type").from("route").equalTo(Expression.string("route"))
                    .and(Expression.property("type").from("airline").equalTo(Expression.string("airline")))
                    .and(Expression.property("sourceairport").from("route").equalTo(Expression.string("RIX")))
        )
        // </doc>
        
        do {
            for result in try query.execute() {
                print("name property :: \(result.string(forKey: "name")!)")
            }
        }
    }
    
    func dontTestGroupBy() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Function.count(Expression.all())),
                SelectResult.property("country"),
                SelectResult.property("tz"))
            .from(DataSource.database(database))
            .where(
                Expression.property("type").equalTo(Expression.string("airport"))
                    .and(Expression.property("geo.alt").greaterThanOrEqualTo(Expression.int(300)))
            ).groupBy(
                Expression.property("country"),
                Expression.property("tz")
        )
        
        do {
            for result in try query.execute() {
                print("There are \(result.int(forKey: "$1")) airports on the \(result.string(forKey: "tz")!) timezone located in \(result.string(forKey: "country")!) and above 300 ft")
            }
        }
        // </doc>
    }
    
    func dontTestOrderBy() throws {
        database = self.db
        
        // <doc>
        let query = QueryBuilder
            .select(
                SelectResult.expression(Meta.id),
                SelectResult.property("title"))
            .from(DataSource.database(database))
            .where(Expression.property("type").equalTo(Expression.string("hotel")))
            .orderBy(Ordering.property("title").ascending())
            .limit(Expression.int(10))
        // </doc>
        
        print("\(query)")
    }
    
    func dontTestCreateFullTextIndex() throws {
        database = self.db
        
        // <doc>
        // Insert documents
        let tasks = ["buy groceries", "play chess", "book travels", "buy museum tickets"]
        for task in tasks {
            let doc = MutableDocument()
            doc.setString("task", forKey: "type")
            doc.setString(task, forKey: "name")
            try database.saveDocument(doc)
        }
        
        // Create index
        do {
            let index = IndexBuilder.fullTextIndex(items: FullTextIndexItem.property("name")).ignoreAccents(false)
            try database.createIndex(index, withName: "nameFTSIndex")
        } catch let error {
            print(error.localizedDescription)
        }
        // </doc>
    }
    
    func dontTestFullTextSearch() throws {
        database = self.db
        
        // <doc>
        let whereClause = FullTextExpression.index("nameFTSIndex").match("'buy'")
        let query = QueryBuilder
            .select(SelectResult.expression(Meta.id))
            .from(DataSource.database(database))
            .where(whereClause)
        
        do {
            for result in try query.execute() {
                print("document id \(result.string(at: 0)!)")
            }
        } catch let error {
            print(error.localizedDescription)
        }
        // </doc>
    }
    
    // MARK: Replication
    
    func dontTestStartReplication() throws {
        database = self.db
        
        // <doc>
        let url = URL(string: "ws://localhost:4984/db")!
        let target = URLEndpoint(url: url)
        let config = ReplicatorConfiguration(database: database, target: target)
        config.replicatorType = .pull
        
        self.replicator = Replicator(config: config)
        self.replicator.start()
        // </doc>
    }
    
    func dontTestEnableReplicatorLogging() throws {
        // <doc>
        // Replicator
        Database.setLogLevel(.verbose, domain: .replicator)
        // Network
        Database.setLogLevel(.verbose, domain: .network)
        // </doc>
    }
    
    func dontTestReplicatorStatus() throws {
        // <doc>
        self.replicator.addChangeListener { (change) in
            if change.status.activity == .stopped {
                print("Replication stopped")
            }
        }
        // </doc>
    }
    
    func dontTestHandlingReplicationError() throws {
        // <doc>
        self.replicator.addChangeListener { (change) in
            if let error = change.status.error as NSError? {
                print("Error code :: \(error.code)")
            }
        }
        // </doc>
    }
    
    func dontTestCertificatePinning() throws {
        let url = URL(string: "wss://localhost:4985/db")!
        let target = URLEndpoint(url: url)
        
        // <doc>
        let data = try self.dataFromResource(name: "cert", ofType: "cer")
        let certificate = SecCertificateCreateWithData(nil, data)

        let config = ReplicatorConfiguration(database: database, target: target)
        config.pinnedServerCertificate = certificate
        // </doc>
        
        print("\(config)")
    }
    
}
