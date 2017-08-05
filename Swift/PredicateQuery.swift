//
//  PredicateQuery.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A compiled database query, similar to a N1QL or SQL query.
public class PredicateQuery {
    
    /// Creates a database query from the component pieces of a SELECT statement, all of
    /// which are optional except FROM.
    ///
    /// - Parameters:
    ///   - db: The database.
    ///   - wherePredicate: The where predicate.
    ///   - groupBy: The groupby expressions.
    ///   - having: THe having predicate.
    ///   - returning: The returning values.
    ///   - distinct: The distinct flag.
    ///   - orderBy: The order by as an array of the SortDescriptor objects.
    public init(from db: Database,
                where wherePredicate: Predicate? = nil,
                groupBy: [PredicateExpression]? = nil,
                having: Predicate? = nil,
                returning: [PredicateExpression]? = nil,
                distinct: Bool = false,
                orderBy: [SortDescriptor]? = nil)
    {
        database = db
        _impl = db._impl.createQueryWhere(wherePredicate)
        _impl.distinct = distinct
        _impl.orderBy = orderBy
        _impl.groupBy = groupBy
        _impl.having = having
        _impl.returning = returning
    }

    
    /// The database being queried.
    public let database: Database

    
    /// The number of result rows to skip; corresponds to the OFFSET property of a SQL or N1QL query.
    /// This can be useful for "paging" through a large query, but skipping many rows is slow.
    /// Defaults to 0.
    public var offset: UInt = 0

    
    /// The maximum number of rows to return; corresponds to the LIMIT property of a SQL or N1QL query.
    /// Defaults to unlimited.
    public var limit: UInt = UInt.max


    /// Values to substitute for placeholder parameters defined in the query. Defaults to nil.
    /// The dictionary's keys are parameter names, and values are the values to use.
    /// All parameters must be given values before running the query, or it will fail.
    public var parameters: [String : Any] = [:]


    /// Checks whether the query is valid without running it.
    ///
    /// - Throws: An error if the query is not valid.
    public func check() throws {
        try _impl.check()
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
    /// - Returns: The compilied query description.
    /// - Throws: An error if the query is not valid.
    public func explain() throws -> String {
        return try _impl.explain()
    }

    
    /// Runs the query, using the current settings (skip, limit, parameters), returning an enumerator
    /// that returns result rows one at a time.
    /// You can run the query any number of times, and you can even have multiple enumerators active at
    /// once.
    /// The results come from a snapshot of the database taken at the moment -run: is called, so they
    /// will not reflect any changes made to the database afterwards.
    ///
    /// - Returns: The QueryIterator object.
    /// - Throws: An error on a failure.
    public func run() throws -> QueryIterator {
        _impl.offset = offset
        _impl.limit = limit
        _impl.parameters = parameters
        return try QueryIterator(database: database, enumerator: _impl.run())
    }

    
    /// A convenience method equivalent to -run: except that its enumerator returns Documents
    /// directly, not QueryRows.
    ///
    /// - Returns: The DocumentIterator.
    /// - Throws: An error on a failure.
    public func allDocuments() throws -> DocumentIterator {
        return try DocumentIterator(database: database, enumerator: _impl.allDocuments())
    }


    private let _impl: CBLPredicateQuery
}



/// Either NSPredicates or Strings can be used for a Query's "where" and "having" clauses.
public protocol Predicate { }
extension NSPredicate : Predicate { }
extension String : Predicate { }


/// Either NSExpressions or Strings can be used for a Query's "groupBy" and "returning" clauses.
public protocol PredicateExpression { }
extension NSExpression : PredicateExpression { }
extension String : PredicateExpression { }


/// NSExpressions, NSSortDescriptors, or Strings can be used for a Query's "orderBy" clause.
public protocol SortDescriptor { }
extension NSExpression : SortDescriptor { }
extension NSSortDescriptor : SortDescriptor { }
extension String : SortDescriptor { }



/// An iterator of Documents in a Database,
/// returned by Database.allDocuments or Query.allDocuments.
public struct DocumentIterator : Sequence, IteratorProtocol {

    public typealias Element = Document

    public mutating func next() -> Document? {
        if let doc = _enumerator.nextObject() as? CBLDocument {
            return Document(doc)
        } else {
            return nil
        }
    }

    init(database: Database, enumerator: NSEnumerator) {
        _database = database
        _enumerator = enumerator
    }

    let _database: Database
    let _enumerator: NSEnumerator
}



/// The iterator that returns successive rows from a Query.
public struct QueryIterator : Sequence, IteratorProtocol {

    public typealias Element = QueryRow

    public mutating func next() -> QueryRow? {
        let obj = enumerator.nextObject()
        if let row = obj as? CBLQueryRow {
            return FullTextQueryRow(impl: row, database: database)
        } else if let row = obj as? CBLFullTextQueryRow {
            return QueryRow(impl: row, database: database)
        } else {
            return nil
        }
    }

    let database: Database
    let enumerator: NSEnumerator
}
