//
//  FullTextIndexExpression.swift
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
import CouchbaseLiteSwift_Private

/// Index Expression.
public protocol IndexExpressionProtocol { }

/// Full-Text Index Expression.
public protocol FullTextIndexExpressionProtocol: IndexExpressionProtocol {
    /// Specifies an alias name of the data source in which the index has been created.
    ///
    /// - Parameter alias: The alias name of the data source.
    /// - Returns: The full-text index expression referring to a full text index in the specified data source.
    func `from`(_ alias: String) -> FullTextIndexExpressionProtocol
}

internal class FullTextIndexExpression: FullTextIndexExpressionProtocol {
    var alias: String?
    let name: String
    
    init(alias: String?, name: String) {
        self.alias = alias
        self.name = name
    }
    
    func from(_ alias: String) -> FullTextIndexExpressionProtocol {
        self.alias = alias
        return self
    }
    
    func stringVal() -> String {
        if let alias = self.alias {
            return "\(alias).\(self.name)"
        }
        return self.name
    }
    
    func toImpl() -> CBLQueryFullTextIndexExpressionProtocol {
        return CBLQueryFullTextIndexExpression(stringVal())
    }
}
