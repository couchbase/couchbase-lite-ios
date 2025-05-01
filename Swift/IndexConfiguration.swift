//
//  IndexConfiguration.swift
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
import CouchbaseLiteSwift_Private

/// Configuration for creating indexes.
public protocol IndexConfiguration { }

/// Configuration for creating full-text indexes.
public struct FullTextIndexConfiguration: IndexConfiguration, IndexConfigConvertable {
    /// Gets the expressions to use to create the index.
    public let expressions: [String]
    
    /// A predicate expression defining conditions for indexing documents.
    /// Only documents satisfying the predicate are included, enabling partial indexes.
    public let `where`: String?
    
    /// Set the true value to ignore accents/diacritical marks.
    /// The default value is ``FullTextIndexConfiguration.defaultIgnoreAccents``.
    public let ignoreAccents: Bool

    /// The language code which is an ISO-639 language such as "en", "fr", etc.
    /// Setting the language code affects how word breaks and word stems are parsed.
    /// Without setting the value, the current locale's language will be used. Setting
    /// a nil or "" value to disable the language features.
    public let language: String?
    
    /// Initializes a full-text index using an array of N1QL expression strings, with an optional where clause for partial indexing.
    ///  - Parameter expressions The array of expression strings.
    ///  - Parameter ignoreAccents Optional to ignore accents/diacritical marks.
    ///  - Parameter language Optional language code which is an ISO-639 language such as "en", "fr", etc.
    ///  - Parameter where Optional where clause for partial indexing.
    ///  - Returns The value index configuration object.
    public init(_ expressions: [String], where: String? = nil, ignoreAccents: Bool? = FullTextIndexConfiguration.defaultIgnoreAccents, language: String? = nil) {
        self.expressions = expressions
        self.ignoreAccents = ignoreAccents ?? FullTextIndexConfiguration.defaultIgnoreAccents
        self.language = language
        self.where = `where`
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLIndexConfiguration {
        return CBLFullTextIndexConfiguration(expression: expressions, where: `where`, ignoreAccents: ignoreAccents, language: language)
    }
}

/// Configuration for creating value indexes.
public struct ValueIndexConfiguration: IndexConfiguration, IndexConfigConvertable {
    /// Gets the expressions to use to create the index.
    public let expressions: [String]
    
    
    /// A predicate expression defining conditions for indexing documents.
    /// Only documents satisfying the predicate are included, enabling partial indexes.
    public let `where`: String?
    
    /// Initializes a value index using an array of N1QL expression strings, with an optional where clause for partial indexing.
    ///  - Parameter expressions The array of expression strings.
    ///  - Parameter where Optional where clause for partial indexing.
    ///  - Returns The value index configuration object.
    public init(_ expressions: [String], where: String? = nil) {
        self.expressions = expressions
        self.where = `where`
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLIndexConfiguration {
        return CBLValueIndexConfiguration(expression: expressions, where: `where`)
    }
}

/// Configuration for indexing property values within nested arrays in documents,
/// intended for use with the UNNEST query.
public struct ArrayIndexConfiguration: IndexConfiguration, IndexConfigConvertable {
    /// Path to the array, which can be nested.
    public let path: String
    
    ///  The expressions representing the values within the array to be indexed.
    public let expressions: [String]?
    
    /// Initializes the configuration with paths to the nested array and the optional
    /// expressions for the values within the arrays to be indexed.
    /// - Parameter path Path to the array, which can be nested to be indexed.
    /// - Note Use "[]" to represent a property that is an array of each nested array level.
    ///     For a single array or the last level array, the "[]" is optional.
    ///     For instance, use "contacts[].phones" to specify an array of phones within each contact.
    /// - Parameter expressions An optional array of strings, where each string
    ///     represents an expression defining the values within the array to be indexed.
    ///     If the array specified by the path contains scalar values, this parameter can be null.
    /// - Returns The ArrayIndexConfiguration object.
    public init(path: String, expressions: [String]? = nil) {
        if let expressions = expressions {
                if expressions.isEmpty || (expressions.count == 1 && expressions[0].isEmpty) {
                    NSException(name: .invalidArgumentException,
                                reason: "Empty expressions is not allowed, use nil instead",
                                userInfo: nil).raise()
                }
        }
        self.path = path
        self.expressions = expressions
    }
    
    // MARK: Internal
    
    func toImpl() -> CBLIndexConfiguration {
        return CBLArrayIndexConfiguration(path: path, expressions: expressions)
    }
}


// MARK: Internal

protocol IndexConfigConvertable {
    func toImpl() -> CBLIndexConfiguration
}

extension IndexConfiguration {
    func toImpl() -> CBLIndexConfiguration {
        if let index = self as? IndexConfigConvertable {
            return index.toImpl()
        }
        fatalError("Unsupported Index")
    }
}
