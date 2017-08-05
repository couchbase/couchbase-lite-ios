//
//  Query.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A database query.
/// A Query instance can be constructed by calling one of the select class methods.
public class Query {
    
    /// Returns the Parameters object used for setting values to the query parameters defined
    /// in the query. All parameters defined in the query must be given values
    /// before running the query, or the query will fail.
    public var parameters: Parameters {
        if params == nil {
            params = Parameters(params: nil)
        }
        return params!
    }
    
    
    /// Create a SELECT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select object.
    public static func select(_ results: SelectResult...) -> Select {
        return Select(impl: SelectResult.toImpl(results: results), distinct: false)
    }
    
    
    /// Create a SELECT DISTINCT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select distinct object.
    public static func selectDistinct(_ results: SelectResult...) -> Select {
        return Select(impl: SelectResult.toImpl(results: results), distinct: true)
    }
    

    /// Runs the query. The returning an enumerator that returns result rows one at a time.
    /// You can run the query any number of times, and you can even have multiple enumerators active 
    /// at once.
    ///
    /// The results come from a snapshot of the database taken at the moment -run: is called, so they
    /// will not reflect any changes made to the database afterwards.
    ///
    /// - Returns: The ResultSet object representing the query result.
    /// - Throws: An error on failure, or if the query is invalid.
    public func run() throws -> ResultSet {
        prepareQuery()
        applyParameters()
        return try ResultSet(impl: queryImpl!.run())
    }
    
    
    /// Returns a string describing the implementation of the compiled query.
    /// This is intended to be read by a developer for purposes of optimizing the query, especially
    /// to add database indexes. It's not machine-readable and its format may change.
    ///
    /// As currently implemented, the result is two or more lines separated by newline characters:
    /// * The first line is the SQLite SELECT statement.
    /// * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
    /// statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
    /// important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
    /// slow linear scan of the documents instead of using an index.
    ///
    /// - Returns: The implementation detail of the compiled query.
    /// - Throws: An error if the query is not valid.
    public func explain() throws -> String {
        prepareQuery()
        return try queryImpl!.explain()
    }
    
    
    /// Returns a live query based on the current query.
    ///
    /// - Returns: a live query object.
    public func toLive() -> LiveQuery {
        prepareQuery()
        return LiveQuery(database: database!, impl: queryImpl!.toLive(), params: params)
    }

    // MARK: Internal
    
    var selectImpl: [CBLQuerySelectResult]?
    
    var distinct = false
    
    var fromImpl: CBLQueryDataSource?
    
    var joinsImpl: [CBLQueryJoin]?
    
    var database: Database?
    
    var whereImpl: CBLQueryExpression?
    
    var groupByImpl: [CBLQueryExpression]?
    
    var havingImpl: CBLQueryExpression?
    
    var orderingsImpl: [CBLQueryOrdering]?
    
    var limitImpl: CBLQueryLimit?
    
    var queryImpl: CBLQuery?
    
    var params: Parameters?
    
    init() { }
    
    func prepareQuery() {
        if queryImpl != nil {
            return
        }
        
        precondition(fromImpl != nil, "From statement is required.")
        assert(selectImpl != nil && database != nil)
        if self.distinct {
            queryImpl = CBLQuery.selectDistinct(
                selectImpl!,
                from: fromImpl!,
                join: joinsImpl,
                where: whereImpl,
                groupBy: groupByImpl,
                having: havingImpl,
                orderBy: orderingsImpl,
                limit: limitImpl)
        } else {
            queryImpl = CBLQuery.select(
                selectImpl!,
                from: fromImpl!,
                join: joinsImpl,
                where: whereImpl,
                groupBy: groupByImpl,
                having: havingImpl,
                orderBy: orderingsImpl,
                limit: limitImpl)
        }
    }
    
    func applyParameters() {
        if let p = self.params, let paramDict = p.params {
            for (name, value) in paramDict {
                queryImpl!.parameters.setObject(value, forName: name)
            }
        }
    }

    func copy(_ query: Query) {
        self.database = query.database
        self.selectImpl = query.selectImpl
        self.distinct = query.distinct
        self.fromImpl = query.fromImpl
        self.joinsImpl = query.joinsImpl
        self.whereImpl = query.whereImpl
        self.groupByImpl = query.groupByImpl
        self.havingImpl = query.havingImpl
        self.orderingsImpl = query.orderingsImpl
        self.limitImpl = query.limitImpl
        
        if let queryParams = query.params {
            self.params = queryParams.copy()
        }
    }
    
}
