//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


extension Database {
    /** Creates a value index (type kValueIndex) on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be Expression, 
                         NSExpression objects, or NSStrings that are expression format strings.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True on success, false on failure. */
    public func createIndex(_ expressions: [Expression]) throws {
        try _impl.createIndex(on: expressions)
    }


    /** Creates an index on a given document property.
     This will speed up queries that test that property, at the expense of making database writes a
     little bit slower.
     @param expressions  Expressions to index, typically key-paths. Can be Expression, 
                         NSExpression objects, or NSStrings that are expression format strings.
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
        
        var expImpls: [CBLQueryExpression] = []
        for exp in expressions {
            expImpls.append(exp.impl)
        }

        if let language = language {
            try language.withCString({ (cLanguage: UnsafePointer<Int8>) in
                cblOptions.language = cLanguage
                try _impl.createIndex(on: expImpls, type: cblType, options: &cblOptions)
            })
        } else {
            try _impl.createIndex(on: expImpls, type: cblType, options: &cblOptions)
        }
    }


    /** Deletes an existing index. Returns NO if the index did not exist.
     @param expressions  Expressions indexed (same parameter given to -createIndexOn:.)
     @param type  Type of index.
     @param error  If an error occurs, it will be stored here if this parameter is non-NULL.
     @return  True if the index existed and was deleted, false if it did not exist. */
    public func deleteIndex(_ expressions: [Expression], type: IndexType) throws {
        var expImpls: [CBLQueryExpression] = []
        for exp in expressions {
            expImpls.append(exp.impl)
        }
        try _impl.deleteIndex(on: expImpls, type: type)
    }
}


public typealias IndexType = CBLIndexType


/** Specifies the type of index to create, and parameters for certain types of indexes. */
public enum IndexOptions {
    /** Regular value index. */
    case valueIndex
    /** Full-Text search index. */
    case fullTextIndex (language: String?, ignoreDiacritics: Bool)
    /** Geo searcg index. */
    case geoIndex
}
