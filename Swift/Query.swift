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
    
    /** Create a SELECT ALL (*) statement instance. You can then call the Select instance's
        methods such as from() method to construct the complete Query instance. */
    public static func select() -> Select {
        return Select(impl: CBLQuerySelect.all(), distict: false)
    }
    
    /** Create a SELECT DISTINCT ALL (*) statement instance. You can then call the Select instance's
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
            try prepareQuery()
        }
        
        return try QueryIterator(database: database, enumerator: queryImpl!.run())
    }
    
    /** Returns a string describing the implementation of the compiled query.
        This is intended to be read by a developer for purposes of optimizing the query, especially
        to add database indexes. It's not machine-readable and its format may change.
     
        As currently implemented, the result is two or more lines separated by newline characters:
        * The first line is the SQLite SELECT statement.
        * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
          statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
          important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
          slow linear scan of the documents instead of using an index.
        @param outError If an error occurs, it will be stored here if this parameter is non-NULL.
        @return a string describing the implementation of the compiled query. */
    public func explain() throws -> String {
        if queryImpl == nil {
            try prepareQuery()
        }
        return try queryImpl!.explain()
    }
    
    /** Returns a live query based on the current query.
        @return a live query object. */
    public func toLive() throws -> LiveQuery {
        guard let database = database else {
            throw CouchbaseLiteError.invalidQuery
        }
        
        if queryImpl == nil {
            try prepareQuery()
        }
        
        return LiveQuery(database: database, impl: queryImpl!.toLive())
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
    
    func prepareQuery() throws {
        guard let selectImpl = selectImpl, let fromImpl = fromImpl else {
            throw CouchbaseLiteError.invalidQuery
        }

        if self.distinct {
            queryImpl = CBLQuery.selectDistinct(
                selectImpl, from: fromImpl, where: whereImpl, orderBy: orderByImpl)
        } else {
            queryImpl = CBLQuery.select(
                selectImpl, from: fromImpl, where: whereImpl, orderBy: orderByImpl)
        }
    }

    func copy(_ query: Query) {
        self.database = query.database
        self.selectImpl = query.selectImpl
        self.distinct = query.distinct
        self.fromImpl = query.fromImpl
        self.whereImpl = query.whereImpl
        self.orderByImpl = query.orderByImpl
    }
    
}
