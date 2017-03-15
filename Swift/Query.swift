//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** A compiled database query, similar to a N1QL or SQL query. */
public class Query {

    /** Creates a database query from the component pieces of a SELECT statement, all of
        which are optional except FROM. */
    public init(from db: Database,
                where wher: Predicate? = nil,
                groupBy: [Expression]? = nil,
                having: Predicate? = nil,
                returning: [Expression]? = nil,
                distinct: Bool = false,
                orderBy: [SortDescriptor]? = nil)
    {
        database = db
        _impl = db._impl.createQueryWhere(wher)
        _impl.distinct = distinct
        _impl.orderBy = orderBy
        _impl.groupBy = groupBy
        _impl.having = having
        _impl.returning = returning
    }

    
    /** The database being queried. */
    public let database: Database


    /** The number of result rows to skip; corresponds to the OFFSET property of a SQL or N1QL query.
        This can be useful for "paging" through a large query, but skipping many rows is slow.
        Defaults to 0. */
    public var offset: UInt = 0


    /** The maximum number of rows to return; corresponds to the LIMIT property of a SQL or N1QL query.
        Defaults to unlimited. */
    public var limit: UInt = UInt.max


    /** Values to substitute for placeholder parameters defined in the query. Defaults to nil.
        The dictionary's keys are parameter names, and values are the values to use.
        All parameters must be given values before running the query, or it will fail. */
    public var parameters: [String : Any] = [:]


    /** Checks whether the query is valid without running it. */
    public func check() throws {
        try _impl.check()
    }


    /** Returns a string describing the implementation of the compiled query.
        This is intended to be read by a developer for purposes of optimizing the query, especially
        to add database indexes. It's not machine-readable and its format may change.

        As currently implemented, the result is two or more lines separated by newline characters:
        * The first line is the SQLite SELECT statement.
        * The subsequent lines are the output of SQLite's "EXPLAIN QUERY PLAN" command applied to that
        statement; for help interpreting this, see https://www.sqlite.org/eqp.html . The most
        important thing to know is that if you see "SCAN TABLE", it means that SQLite is doing a
        slow linear scan of the documents instead of using an index. */
    public func explain() throws -> String {
        return try _impl.explain()
    }


    /** Runs the query, using the current settings (skip, limit, parameters), returning an enumerator
        that returns result rows one at a time.
        You can run the query any number of times, and you can even have multiple enumerators active at
        once.
        The results come from a snapshot of the database taken at the moment -run: is called, so they
        will not reflect any changes made to the database afterwards. */
    public func run() throws -> QueryIterator {
        _impl.offset = offset
        _impl.limit = limit
        _impl.parameters = parameters
        return try QueryIterator(database: database, enumerator: _impl.run())
    }


    /** A convenience method equivalent to -run: except that its enumerator returns Documents
        directly, not QueryRows. */
    public func allDocuments() throws -> DocumentIterator {
        return try DocumentIterator(database: database, enumerator: _impl.allDocuments())
    }


    private let _impl: CBLPredicateQuery
}



/** Either NSPredicates or Strings can be used for a Query's "where" and "having" clauses. */
public protocol Predicate { }
extension NSPredicate : Predicate { }
extension String : Predicate { }


/** Either NSExpressions or Strings can be used for a Query's "groupBy" and "returning" clauses. */
public protocol Expression { }
extension NSExpression : Expression { }
extension String : Expression { }


/** NSExpressions, NSSortDescriptors, or Strings can be used for a Query's "orderBy" clause. */
public protocol SortDescriptor { }
extension NSExpression : SortDescriptor { }
extension NSSortDescriptor : SortDescriptor { }
extension String : SortDescriptor { }



/** An iterator of Documents in a Database,
    returned by Database.allDocuments or Query.allDocuments. */
public struct DocumentIterator : Sequence, IteratorProtocol {

    public typealias Element = Document

    public mutating func next() -> Document? {
        if let doc = _enumerator.nextObject() as? CBLDocument {
            return Document(doc, inDatabase: _database)
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



/** The iterator that returns successive rows from a Query. */
public struct QueryIterator : Sequence, IteratorProtocol {

    public typealias Element = QueryRow

    public mutating func next() -> QueryRow? {
        if let row = enumerator.nextObject() as? CBLQueryRow {
            return QueryRow(impl: row, database: database)
        } else {
            return nil
        }
    }

    let database: Database
    let enumerator: NSEnumerator
}



/** A row of data generated by a Query. */
public struct QueryRow {

    /** The ID of the document that produced this row. */
    public var documentID: String {return impl.documentID}

    /** The sequence number of the document revision that produced this row. */
    public var sequence: UInt64 {return impl.sequence}

    /** The document that produced this row. */
    public var document: Document {
        return Document(impl.document, inDatabase: database)
    }


    /** The result value at the given index (if the query has a "returning" specification.) */
    public func value(at index: Int) -> Any? {
        return impl.value(at: UInt(index))
    }

    public subscript(index: Int) -> Bool {
        return impl.boolean(at: UInt(index))
    }

    public subscript(index: Int) -> Int {
        return impl.integer(at: UInt(index))
    }

    public subscript(index: Int) -> Float {
        return impl.float(at: UInt(index))
    }

    public subscript(index: Int) -> Double {
        return impl.double(at: UInt(index))
    }

    public subscript(index: Int) -> String? {
        return impl.string(at: UInt(index))
    }

    public subscript(index: Int) -> Date? {
        return impl.date(at: UInt(index))
    }

    public subscript(index: Int) -> [Any]? {
        return impl.value(at: UInt(index)) as? [Any]
    }

    public subscript(index: Int) -> [String:Any]? {
        return impl.value(at: UInt(index)) as? [String:Any]
    }

    public subscript(index: Int) -> Any? {
        return impl.value(at: UInt(index))
    }


    let impl: CBLQueryRow
    let database: Database
}


