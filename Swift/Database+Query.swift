//
//  Query.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/10/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


// MARK: - <#Description#>
extension Database {
    
    /// Creates a value index (type kValueIndex) on a given document property.
    /// This will speed up queries that test that property, at the expense of making database writes 
    /// a little bit slower.
    ///
    /// - Parameter expressions: Expressions to index, typically key-paths. Can be Expression objects,
    ///                          NSExpression objects, or Strings that are expression format strings.
    /// - Throws: An error on failure.
    public func createIndex(_ expressions: [Any]) throws {
        try _impl.createIndex(on: expressions)
    }

    
    /// Creates an index on a given document property.
    /// This will speed up queries that test that property, at the expense of making database writes 
    /// a little bit slower.
    ///
    /// - Parameters:
    ///   - expressions: Expressions to index, typically key-paths. Can be Expression objects,
    ///                  NSExpression objects, or Strings that are expression format strings.
    ///   - options: Options affecting the index, or NULL for default settings.
    /// - Throws: An error on failure.
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
        
        var expImpls: [Any] = []
        for exp in expressions {
            if let x = exp as? Expression {
                expImpls.append(x.impl)
            } else {
                expImpls.append(exp)
            }
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

    
    /// Deletes an existing index. Returns NO if the index did not exist.
    ///
    /// - Parameters:
    ///   - expressions: Expressions indexed (same parameter given to -createIndexOn:.)
    ///   - type: Type of index.
    /// - Throws: An error on failure.
    public func deleteIndex(_ expressions: [Any], type: IndexType) throws {
        var expImpls: [Any] = []
        for exp in expressions {
            if let x = exp as? Expression {
                expImpls.append(x.impl)
            } else {
                expImpls.append(exp)
            }
        }
        try _impl.deleteIndex(on: expImpls, type: type)
    }
    
}


/// IndexType.
public typealias IndexType = CBLIndexType

/// Specifies the type of index to create, and parameters for certain types of indexes.
///
/// - valueIndex:  Regular value index.
/// - fullTextIndex: Full-Text search index.
/// - geoIndex: Geo searcg index.
public enum IndexOptions {
    case valueIndex
    case fullTextIndex (language: String?, ignoreDiacritics: Bool)
    case geoIndex
}
