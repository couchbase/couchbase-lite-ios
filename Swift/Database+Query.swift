//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


extension Database {

    /** An iterator over all documents in the database, ordered by document ID. */
    public var allDocuments: DocumentIterator {
        return DocumentIterator(database: self, enumerator: _impl.allDocuments())
    }

     /** Compiles a database query, from any of several input formats.
     Once compiled, the query can be run many times with different parameter values.
     The rows will be sorted by ascending document ID, and no custom values are returned.
     @param where  The query specification. This can be an NSPredicate, or an NSString (interpreted
     as an NSPredicate format string), or nil to return all documents.
     @return  The Query. */
    public func createQueryWhere(_ wher: Any?) -> Query {
        return Query(impl: _impl.createQueryWhere(nil), inDatabase: self, where: wher)
    }


    /** Creates a value index (type kValueIndex) on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
     or NSStrings that are expression format strings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Any]) throws {
        try _impl.createIndex(on: expressions)
    }


    /** Creates an index on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
     or NSStrings that are expression format strings.
     @param type  Type of index to create (value, full-text or geospatial.)
     @param options  Options affecting the index, or NULL for default settings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Any], options: IndexOptions) throws {
        var cblType: CBLIndexType
        var cblOptions = CBLIndexOptions()
        var language: String?
        switch(options) {
        case .valueIndex:
            cblType = CBLIndexType.valueIndex
        case .fullTextIndex(let lang, let ignoreDiacritics):
            cblType = CBLIndexType.fullTextIndex
            language = lang
            cblOptions.ignoreDiacritics = ObjCBool(ignoreDiacritics)
        case .geoIndex:
            cblType = CBLIndexType.geoIndex
        }

        if let language = language {
            try language.withCString({ (cLanguage: UnsafePointer<Int8>) in
                cblOptions.language = cLanguage
                try _impl.createIndex(on: expressions, type: cblType, options: &cblOptions)
            })
        } else {
            try _impl.createIndex(on: expressions, type: cblType, options: &cblOptions)
        }
    }


    /** Deletes an existing index. Returns NO if the index did not exist.
     @param expressions  Expressions indexed (same parameter given to -createIndexOn:.)
     @param type  Type of index.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True if the index existed and was deleted, false if it did not exist. */
    public func deleteIndex(on expressions: [Any], type: IndexType) throws {
        try deleteIndex(on: expressions, type: type)
    }

}


/** An iterator of Documents in a Database, returned by Database.allDocuments */
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
