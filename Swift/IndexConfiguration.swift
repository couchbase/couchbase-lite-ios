//
//  IndexConfiguration.swift
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

public protocol IndexConfiguration { }

public class FullTextIndexConfiguration: IndexConfiguration, IndexConfigConvertable {
    
    /// Gets the expressions to use to create the index.
    public var expressions: [String] {
        return self.impl.expressions
    }
    
    /// Set the true value to ignore accents/diacritical marks. The default value is false.
    public var ignoreAccents: Bool {
        return self.impl.ignoreAccents
    }

    /// The language code which is an ISO-639 language such as "en", "fr", etc.
    /// Setting the language code affects how word breaks and word stems are parsed.
    /// Without setting the value, the current locale's language will be used. Setting
    /// a nil or "" value to disable the language features.
    public var language: String? {
        return self.impl.language
    }
    
    /// Constructor for creating a full-text index by using an array of N1QL expression strings
    public init(_ expressions: [String], ignoreAccents: Bool? = false, language: String? = nil) {
        self.impl = CBLFullTextIndexConfiguration(expression: expressions,
                                                  ignoreAccents: ignoreAccents ?? false,
                                                  language: language)
    }
    
    // MARK: Internal

    private let impl: CBLFullTextIndexConfiguration
    
    func toImpl() -> CBLIndexConfiguration {
        return impl
    }
}

public class ValueIndexConfiguration: IndexConfiguration, IndexConfigConvertable {
    
    /// Gets the expressions to use to create the index.
    public var expressions: [String] {
        return self.impl.expressions
    }
    
    /// Constructor for creating a value index by using an array of N1QL expression strings.
    public  init(_ expressions: [String]) {
        self.impl = CBLValueIndexConfiguration(expression: expressions)
    }
    
    // MARK: Internal
    
    private let impl: CBLValueIndexConfiguration
    
    func toImpl() -> CBLIndexConfiguration {
        return self.impl
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
        fatalError("Unsupported index.")
    }
    
}
