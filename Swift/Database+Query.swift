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
         Once compiled, the query can be run many times with different parameter values.*/
    public func createQuery(where wher: Predicate? = nil,
                            groupBy: [Expression]? = nil,
                            having: Predicate? = nil,
                            returning: [Expression]? = nil,
                            distinct: Bool = false,
                            orderBy: [SortDescriptor]? = nil) -> Query
    {
        return Query(from: self, where: wher, groupBy: groupBy, having: having,
                     returning: returning, distinct: distinct, orderBy: orderBy)
    }


    /** Creates a value index (type kValueIndex) on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be NSExpression objects,
     or NSStrings that are expression format strings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Expression]) throws {
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
    public func createIndex(_ expressions: [Expression], options: IndexOptions) throws {
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
    public func deleteIndex(on expressions: [Expression], type: IndexType) throws {
        try deleteIndex(on: expressions, type: type)
    }

}


public typealias IndexType = CBLIndexType


/** Specifies the type of index to create, and parameters for certain types of indexes. */
public enum IndexOptions {
    case valueIndex
    case fullTextIndex (language: String?, ignoreDiacritics: Bool)
    case geoIndex
}
