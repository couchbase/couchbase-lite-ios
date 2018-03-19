//
//  Query.swift
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

import Foundation


/// A database query.
/// A Query instance can be constructed by calling one of the select class methods.
public class Query {
    
    /// A Parameters object used for setting values to the query parameters defined
    /// in the query. All parameters defined in the query must be given values
    /// before running the query, or the query will fail.
    ///
    /// The returned Parameters object will be readonly.
    public var parameters: Parameters? {
        get {
            return params
        }
        set {
            if let p = newValue {
                params = Parameters(parameters: p, readonly: true)
            } else {
                params = nil
            }
            applyParameters()
        }
    }
    

    /// Executes the query. The returning an enumerator that returns result rows one at a time.
    /// You can run the query any number of times, and you can even have multiple enumerators active 
    /// at once.
    ///
    /// The results come from a snapshot of the database taken at the moment -run: is called, so they
    /// will not reflect any changes made to the database afterwards.
    ///
    /// - Returns: The ResultSet object representing the query result.
    /// - Throws: An error on failure, or if the query is invalid.
    public func execute() throws -> ResultSet {
        applyParameters()
        return try ResultSet(impl: queryImpl!.execute())
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
    
    
    /// Adds a query change listener. Changes will be posted on the main queue.
    ///
    /// - Parameter listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addChangeListener(
        _ listener: @escaping (QueryChange) -> Void) -> ListenerToken {
        return self.addChangeListener(withQueue: nil, listener)
    }
    
    
    /// Adds a query change listener with the dispatch queue on which changes
    /// will be posted. If the dispatch queue is not specified, the changes will be
    /// posted on the main queue.
    ///
    /// - Parameters:
    ///   - queue: The dispatch queue.
    ///   - listener: The listener to post changes.
    /// - Returns: An opaque listener token object for removing the listener.
    @discardableResult public func addChangeListener(withQueue queue: DispatchQueue?,
        _ listener: @escaping (QueryChange) -> Void) -> ListenerToken {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        prepareQuery()
        let token = self.queryImpl!.addChangeListener(with: queue, listener: {
            [unowned self] (change) in
            let rows: ResultSet?;
            if let rs = change.results {
                rows = ResultSet(impl: rs)
            } else {
                rows = nil;
            }
            listener(QueryChange(query: self, results: rows, error: change.error))
        })
        
        if tokens.count == 0 {
            database!.addQuery(self)
        }
        
        let listenerToken = ListenerToken(token)
        tokens.add(listenerToken)
        return listenerToken
    }
    
    
    /// Removes a change listener wih the given listener token.
    ///
    /// - Parameter token: The listener token.
    public func removeChangeListener(withToken token: ListenerToken) {
        lock.lock()
        prepareQuery()
        queryImpl!.removeChangeListener(with: token._impl)
        tokens.remove(token)
        
        if tokens.count == 0 {
            database!.removeQuery(self)
        }
        lock.unlock()
    }

    // MARK: Internal
    
    var params: Parameters?
    
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
    
    var tokens = NSMutableSet()
    
    var lock = NSRecursiveLock()
    
    init() { }
    
    func prepareQuery() {
        lock.lock()
        defer {
            lock.unlock()
        }
        
        if queryImpl != nil {
            return
        }
        
        precondition(fromImpl != nil, "From statement is required.")
        assert(selectImpl != nil && database != nil)
        if self.distinct {
            queryImpl = CBLQueryBuilder.selectDistinct(
                selectImpl!,
                from: fromImpl!,
                join: joinsImpl,
                where: whereImpl,
                groupBy: groupByImpl,
                having: havingImpl,
                orderBy: orderingsImpl,
                limit: limitImpl)
        } else {
            queryImpl = CBLQueryBuilder.select(
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
        lock.lock()
        prepareQuery()
        queryImpl!.parameters = self.params?.toImpl()
        lock.unlock()
    }
    
    func stop() {
        lock.lock()
        database!.removeQuery(self)
        tokens.removeAllObjects()
        lock.unlock()
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
    }
    
}


/// A factory class to create a Select instance.
public final class QueryBuilder {
    
    /// Create a SELECT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select object.
    public static func select(_ results: SelectResultProtocol...) -> Select {
        return select(results)
    }
    
    
    /// Create a SELECT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select object.
    public static func select(_ results: [SelectResultProtocol]) -> Select {
        return Select(impl: QuerySelectResult.toImpl(results: results), distinct: false)
    }
    
    
    /// Create a SELECT DISTINCT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select distinct object.
    public static func selectDistinct(_ results: SelectResultProtocol...) -> Select {
        return selectDistinct(results)
    }
    
    
    /// Create a SELECT DISTINCT statement instance that you can use further
    /// (e.g. calling the from() function) to construct the complete query statement.
    ///
    /// - Parameter results: The array of the SelectResult object for specifying the returned values.
    /// - Returns: A Select distinct object.
    public static func selectDistinct(_ results: [SelectResultProtocol]) -> Select {
        return Select(impl: QuerySelectResult.toImpl(results: results), distinct: true)
    }
    
}


extension Query: CustomStringConvertible {
    
    public var description: String {
        prepareQuery()
        return "\(type(of: self))[\(self.queryImpl!.description)]"
    }
    
}
