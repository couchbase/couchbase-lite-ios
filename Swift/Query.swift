//
//  Query.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** A database query.
 A Query instance can be constructed by calling one of the select class methods. */
public class Query {
    
    /** Create a SELECT ALL (*) statement instance. You can then call the Select's instance 
     methods such as from() method to construct the complete Query instance. */
    public static func select() -> Select {
        return Select(impl: CBLQuerySelect.all(), distict: false)
    }
    
    /** Create a SELECT DISTINCT ALL (*) statement instance. You can then call the Select's instance 
     methods such as from() method to construct the complete Query instance. */
    public static func selectDistinct() -> Select {
        return Select(impl: CBLQuerySelect.all(), distict: true)
    }
    
    /** Runs the query. The returning an enumerator that returns result rows one at a time.
     You can run the query any number of times, and you can even have multiple enumerators active at
     once.
     The results come from a snapshot of the database taken at the moment -run: is called, so they
     will not reflect any changes made to the database afterwards. */
    public func run() throws -> QueryIterator {
        guard let database = database else {
            throw CouchbaseLiteError.invalidQuery
        }
        
        if queryImpl == nil {
            guard let selectImpl = selectImpl, let fromImpl = fromImpl else {
                throw CouchbaseLiteError.invalidQuery
            }
            
            if self.distinct {
                queryImpl = CBLQuery.selectDistict(
                    selectImpl, from: fromImpl, where: whereImpl, orderBy: orderByImpl)
            } else {
                queryImpl = CBLQuery.select(
                    selectImpl, from: fromImpl, where: whereImpl, orderBy: orderByImpl)
            }
        }
        
        return try QueryIterator(database: database, enumerator: queryImpl!.run())
    }
    
    // MARK: Internal
    
    var queryImpl: CBLQuery?
    
    var database: Database?
    
    var selectImpl: CBLQuerySelect?
    
    var distinct = false
    
    var fromImpl: CBLQueryDataSource?
    
    var whereImpl: CBLQueryExpression?
    
    var orderByImpl: CBLQueryOrderBy?
    
    init() { }
    
    func copy(_ query: Query) {
        self.database = query.database
        self.selectImpl = query.selectImpl
        self.distinct = query.distinct
        self.fromImpl = query.fromImpl
        self.whereImpl = query.whereImpl
        self.orderByImpl = query.orderByImpl
    }
    
}
