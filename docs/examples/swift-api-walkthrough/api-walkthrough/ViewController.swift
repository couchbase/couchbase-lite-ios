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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let database: Database
        do {
            database = try Database(name: "my-database")
        } catch let error as NSError {
            NSLog("Cannot open the database: %@", error)
            return
        }
        
        // create document
        let dict: [String: Any] = ["type": "task",
                                   "owner": "todo",
                                   "createdAt": Date()]
        let newTask = Document(dictionary: dict)
        try? database.save(newTask)
        
        // mutate document
        newTask.set("Apples", forKey:"name")
        try? database.save(newTask)
        
        // typed accessors
        newTask.set(Date(), forKey: "createdAt")
        let date = newTask.date(forKey: "createdAt")
        
        // database transaction
        do {
            try database.inBatch {
                for i in 0...10 {
                    let doc = Document()
                    doc.set("user", forKey: "type")
                    doc.set("user \(i)", forKey: "name")
                    try database.save(doc)
                    print("saved user document \(doc.string(forKey: "name"))")
                }
            }
        } catch let error {
            print(error.localizedDescription)
        }
        
        // blob
        let appleImage = UIImage(named: "avatar.jpg")!
        let imageData = UIImageJPEGRepresentation(appleImage, 1)!
        
        let blob = Blob(contentType: "image/jpg", data: imageData)
        newTask.set(blob, forKey: "avatar")
        try? database.save(newTask)
        
        if let taskBlob = newTask.blob(forKey: "image") {
            UIImage(data: taskBlob.content!)
        }
        
        // query
        let query = Query
            .select()
            .from(DataSource.database(database))
            .where(
                Expression.property("type").equalTo("user")
                    .and(Expression.property("admin").equalTo(false))
        )
        
        do {
            let rows = try query.run()
            for row in rows {
                print("doc ID :: \(row.string(forKey: "_id"))")
            }
        } catch let error {
            print(error.localizedDescription)
        }
        
        // fts example
        // Insert documents
        let tasks = ["buy groceries", "play chess", "book travels", "buy museum tickets"]
        for task in tasks {
            let doc = Document()
            doc.set("task", forKey: "type")
            doc.set(task, forKey: "name")
            try? database.save(doc)
        }
        
        // Create index
        do {
            try database.createIndex(["name"], options: .fullTextIndex(language: nil, ignoreDiacritics: false))
        } catch let error {
            print(error.localizedDescription)
        }
        
        let whereClause = Expression.property("name").match("'buy'")
        let ftsQuery = Query.select().from(DataSource.database(database)).where(whereClause)
        
        do {
            let ftsQueryResult = try ftsQuery.run()
            for row in ftsQueryResult {
                print("document properties \(row.string(forKey: "_id"))")
            }
        } catch let error {
            print(error.localizedDescription)
        }
        
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
        let config = ReplicatorConfiguration(database: database, targetURL: url)
        let replication = Replicator(config: config)
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
            
            let document = Document()
            document.set("created on background thread", forKey: "status")
            try? database.save(document)
        }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

