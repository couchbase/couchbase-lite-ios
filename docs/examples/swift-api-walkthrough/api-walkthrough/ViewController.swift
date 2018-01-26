//
//  ViewController.swift
//  api-walkthrough
//
//  Created by James Nocentini on 27/06/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

import UIKit
import CouchbaseLiteSwift

class ViewController: UIViewController {

    var database: Database? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        
        var config = DatabaseConfiguration()
        config.conflictResolver = ExampleConflictResolver()
        let database: Database
        do {
            database = try Database(name: "my-database", config: config)
        } catch let error as NSError {
            NSLog("Cannot open the database: %@", error)
            return
        }
        
        // create document
        let dict: [String: Any] = ["type": "task",
                                   "owner": "todo",
                                   "createdAt": Date()]
        let newTask = MutableDocument(withData: dict)
        try? database.saveDocument(newTask)
        
        // mutate document
        newTask.setValue("Apples", forKey:"name")
        try? database.saveDocument(newTask)
        
        // typed accessors
        newTask.setValue(Date(), forKey: "createdAt")
        let date = newTask.date(forKey: "createdAt")
        
        // database transaction
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
        
        // blob
        let appleImage = UIImage(named: "avatar.jpg")!
        let imageData = UIImageJPEGRepresentation(appleImage, 1)!
        
        let blob = Blob(contentType: "image/jpg", data: imageData)
        newTask.setBlob(blob, forKey: "avatar")
        try? database.saveDocument(newTask)
        
        if let taskBlob = newTask.blob(forKey: "image") {
            let image = UIImage(data: taskBlob.content!)
        }
        
        // query
        let query = Query
            .select(SelectResult.expression(Expression.property("name")))
            .from(DataSource.database(database))
            .where(
                Expression.property("type").equalTo("user")
                    .and(Expression.property("admin").equalTo(false))
        )
        
        do {
            let rows = try query.execute()
            for row in rows {
                print("user name :: \(row.string(forKey: "name")!)")
            }
        } catch let error {
            print(error.localizedDescription)
        }
        
        // fts example
        // Insert documents
        let tasks = ["buy groceries", "play chess", "book travels", "buy museum tickets"]
        for task in tasks {
            let doc = MutableDocument()
            doc.setString("task", forKey: "type")
            doc.setString(task, forKey: "name")
            try? database.saveDocument(doc)
        }
        
        // Create index
        do {
            let index = Index.fullTextIndex(withItems: FullTextIndexItem.property("name"))
                .locale(nil)
                .ignoreAccents(false)
            try database.createIndex(index, withName: "name-idx")
        } catch let error {
            print(error.localizedDescription)
        }
        
        let whereClause = FullTextExpression.index("name").match("'buy'")
        let ftsQuery = Query.select().from(DataSource.database(database)).where(whereClause)
        
        do {
            let ftsQueryResult = try ftsQuery.execute()
            for row in ftsQueryResult {
                print("document properties \(row.string(forKey: "_id")!)")
            }
        } catch let error {
            print(error.localizedDescription)
        }
        
        // create conflict
        /*
         * 1. Create a document twice with the same ID.
         * 2. The `theirs` properties in the conflict resolver represents the current rev and
         * `mine` is what's being saved.
         * 3. Read the document after the second save operation and verify its property is as expected.
         */
        let theirs = MutableDocument(withID: "buzz")
        theirs.setString("theirs", forKey: "status")
        let mine = MutableDocument(withID: "buzz")
        mine.setString("mine", forKey: "status")
        do {
            try database.saveDocument(theirs)
            try database.saveDocument(mine)
        } catch let error {
            print(error.localizedDescription)
        }
        
        let conflictResolverResult = database.document(withID: "buzz")
        print("conflictResolverResult doc.status ::: \(conflictResolverResult!.string(forKey: "status")!)")
        
        // replication
        /**
         * Tested with SG 1.5 https://www.couchbase.com/downloads
         * Config file:
         * {
            "databases": {
                "db": {
                    "server":"walrus:",
                    "users": {
                        "GUEST": {"disabled": false, "admin_channels": ["*"]}
                    },
                    "unsupported": {
                        "replicator_2":true
                    }
                }
            }
         }
        */
        let url = URL(string: "blip://localhost:4984/db")!
        let replConfig = ReplicatorConfiguration(withDatabase: database, targetURL: url)
        let replication = Replicator(withConfig: replConfig)
        replication.start()
        
        // replication change listener
        replication.addChangeListener { (change) in
            if (change.status.activity == .stopped) {
                print("Replication was completed.")
            }
        }
        
        // background thread operation
        DispatchQueue.global(qos: .background).async {
            let database: Database
            do {
                database = try Database(name: "my-database")
            } catch let error {
                print(error.localizedDescription)
                return
            }
            
            let document = MutableDocument()
            document.setString("created on background thread", forKey: "status")
            try? database.saveDocument(document)
        }
        
        // travel sample examples
        loadTravelSample()
        do {
            self.database = try Database(name: "mini-travel-sample")
        } catch {
            return
        }
        selectOverviewQuery()
        joinQuery()
        groupByQuery()
        inOperatorQuery()
        inOperatorSatisfiesQuery()
        metaDocIDQuery()
    }

    func loadTravelSample() {
        let dbPath = Bundle.main.path(forResource: "mini-travel-sample", ofType: "cblite2")!
        let fileManager = FileManager.default
        do {
            let destinationPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CouchbaseLite").appendingPathComponent("mini-travel-sample.cblite2").path
            try fileManager.copyItem(atPath: dbPath, toPath: destinationPath)
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    func metaDocIDQuery() {
        let query = Query.select(
            SelectResult.expression(Expression.meta().id)
        )
        .from(DataSource.database(database!))
        .where(
            Expression.property("type").equalTo("airport")
        )
        do {
            for row in try query.run() {
                print("document ID \(row.string(forKey: "id")))")
            }
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    func selectOverviewQuery() {
        let query = Query.select(
                SelectResult.expression(Expression.property("airportname")),
                SelectResult.expression(Expression.property("city"))
            )
            .from(DataSource.database(database!))
            .where(
                Expression.property("type").equalTo("airport")
                .and(Expression.property("tz").equalTo("Europe/Paris"))
                .and(Expression.property("geo.alt").greaterThanOrEqualTo(300))
            )
        do {
            for row in try query.execute() {
                print("\(row.toDictionary()))")
            }
        } catch {
            
        }
    }
    
    func joinQuery() {
        let query = Query.select(
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
            Expression.property("type").from("route").equalTo("route")
            .and(Expression.property("type").from("airline").equalTo("airline"))
            .and(Expression.property("sourceairport").from("route").equalTo("RIX"))
        )
        do {
            for row in try query.execute() {
                print("\(row.toDictionary()))")
            }
        } catch {
            
        }
    }
    
    func groupByQuery() {
        let query = Query.select(
                SelectResult.expression(Function.count("*")),
                SelectResult.expression(Expression.property("country")),
                SelectResult.expression(Expression.property("tz"))
            )
            .from(DataSource.database(database!))
            .where(
                Expression.property("type").equalTo("airport")
                .and(Expression.property("geo.alt").greaterThanOrEqualTo(300))
            )
            .groupBy(
                Expression.property("country"),
                Expression.property("tz")
            )
        do {
            for row in try query.execute() {
                print("\(row.toDictionary()))")
            }
        } catch {
            
        }
    }
    
    func inOperatorQuery() {
        let countries = ["France", "United States"]
        let query = Query.select(
                SelectResult.expression(Expression.property("name"))
            )
            .from(DataSource.database(database!))
            .where(
                Expression.property("country").in(countries)
                .and(Expression.property("type").equalTo("airline"))
            )
        do {
            for row in try query.run() {
                print("\(row.toDictionary())")
            }
        } catch let error {
            print(error.localizedDescription)
        }
    }

    func inOperatorSatisfiesQuery() {
        let query = Query.select(
                SelectResult.expression(Expression.property("sourceairport"))
            )
            .from(DataSource.database(database!))
            .where(
                Expression.any("FLIGHT_VAR").in(Expression.property("schedule"))
                    .satisfies(Expression.variable("FLIGHT_VAR.flight").equalTo("AF103"))
        )
        do {
            for row in try query.run() {
                print("\(row.toDictionary())")
            }
        } catch let error {
            print(error.localizedDescription)
        }
    }
}

