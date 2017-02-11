//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** A compiled database query.
 You create a query by calling the CBLDatabase method createQueryWhere:. The query can be
 further configured by setting properties before running it. Some properties alter the
 behavior of the query enough to trigger recompilation; it's usually best to set these only
 once and then reuse the CBLQuery object. You can use NSPredicate / NSExpression variables
 to parameterize the query, making it flexible without needing recompilation. Then you just
 set the `parameters` property before running it. */
public class Query {

    /** The database being queried. */
    public let database: Database


    /** Specifies a condition (predicate) that documents have to match; corresponds to the WHERE
     clause of a SQL or N1QL query.
     This can be an NSPredicate, or an NSString (interpreted as an NSPredicate format string),
     or nil to return all documents. Defaults to nil.
     If this property is changed, the query will be recompiled the next time it is run. */
    public var `where`: Any? = nil


    /** An array of NSSortDescriptors or NSStrings, specifying properties or expressions that the
     result rows should be sorted by; corresponds to the ORDER BY clause of a SQL or N1QL query.
     These strings, or sort-descriptor names, can name key-paths or be NSExpresson format strings.
     If nil, no sorting occurs; this is faster but the order of rows is undefined.
     The default value sorts by document ID.
     If this property is changed, the query will be recompiled the next time it is run. */
    public var orderBy: [Any]? = nil


    /** An array of NSExpressions (or expression format strings) describing values to include in each
     result row; corresponds to the SELECT clause of a SQL or N1QL query.
     If nil, only the document ID and sequence number will be available. Defaults to nil.
     If this property is changed, the query will be recompiled the next time it is run. */
    public var returning: [Any]? = nil


    /** An array of NSExpressions (or expression format strings) describing how to group rows
     together: all documents having the same values for these expressions will be coalesced into a
     single row.
     If nil, no grouping is done. Defaults to nil. */
    public var groupBy: [Any]? = nil


    /** Specifies a condition (predicate) that grouped rows have to match; corresponds to the HAVING
     clause of a SQL or N1QL query.
     This can be an NSPredicate, or an NSString (interpreted as an NSPredicate format string),
     or nil to not filter groups. Defaults to nil.
     If this property is changed, the query will be recompiled the next time it is run. */
    public var having: Any? = nil


    /** If YES, duplicate result rows will be removed so that all rows are unique;
     corresponds to the DISTINCT keyword of a SQL or N1QL query.
     Defaults to NO. */
    public var distinct: Bool = false


    /** The number of result rows to skip; corresponds to the OFFSET property of a SQL or N1QL query.
     This can be useful for "paging" through a large query, but skipping many rows is slow.
     Defaults to 0. */
    public var offset: UInt = 0


    /** The maximum number of rows to return; corresponds to the LIMIT property of a SQL or N1QL query.
     Defaults to NSUIntegerMax (i.e. unlimited.) */
    public var limit: UInt = UInt.max


    /** Values to substitute for placeholder parameters defined in the query. Defaults to nil.
     The dictionary's keys are parameter names, and values are the values to use.
     All parameters must be given values before running the query, or it will fail. */
    public var parameters: [String : Any]? = nil


    /** Checks whether the query is valid, recompiling it if necessary, without running it. */
    public func check() throws {
        _impl.where = self.where
        _impl.orderBy = orderBy
        _impl.groupBy = groupBy
        _impl.returning = returning
        _impl.having = having
        _impl.distinct = distinct
        _impl.offset = offset
        _impl.limit = limit
        _impl.parameters = parameters
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
        try check()
        return try _impl.explain()
    }


    /** Runs the query, using the current settings (skip, limit, parameters), returning an enumerator
     that returns result rows one at a time.
     You can run the query any number of times, and you can even have multiple enumerators active at
     once.
     The results come from a snapshot of the database taken at the moment -run: is called, so they
     will not reflect any changes made to the database afterwards. */
    public func run() throws -> QueryIterator {
        try check()
        return try QueryIterator(database: database, enumerator: _impl.run())
    }


    /** A convenience method equivalent to -run: except that its enumerator returns CBLDocuments
     directly, not CBLQueryRows. */
    public func allDocuments() throws -> DocumentIterator {
        try check()
        return try DocumentIterator(database: database, enumerator: _impl.allDocuments())
    }


    init(impl: CBLQuery, inDatabase: Database, where: Any? = nil) {
        _impl = impl
        database = inDatabase
        self.where = `where`
    }

    private let _impl: CBLQuery
}



public struct QueryIterator : Sequence, IteratorProtocol {

    public typealias Element = QueryRow

    public mutating func next() -> QueryRow? {
        if let row = _enumerator.nextObject() as? CBLQueryRow {
            return QueryRow(impl: row, inDatabase: _database)
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



public struct QueryRow {

    public var documentID: String {return _impl.documentID}

    public var sequence: UInt64 {return _impl.sequence}

    public var document: Document {
        return Document(_impl.document, inDatabase: database)
    }


    public func value(at index: UInt) -> Any? {
        return _impl.value(at: index)
    }

    public subscript(index: UInt) -> Bool {
        return _impl.boolean(at: index)
    }

    public subscript(index: UInt) -> Int {
        return _impl.integer(at: index)
    }

    public subscript(index: UInt) -> Float {
        return _impl.float(at: index)
    }

    public subscript(index: UInt) -> Double {
        return _impl.double(at: index)
    }

    public subscript(index: UInt) -> String? {
        return _impl.string(at: index)
    }

    public subscript(index: UInt) -> Date? {
        return _impl.date(at: index)
    }

    public subscript(index: UInt) -> Any? {
        return _impl.value(at: index)
    }


    init(impl: CBLQueryRow, inDatabase: Database) {
        _impl = impl
        database = inDatabase
    }

    let _impl: CBLQueryRow
    let database: Database
}
