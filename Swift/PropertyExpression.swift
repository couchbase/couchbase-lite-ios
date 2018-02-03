//
//  PropertyExpression.swift
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


/// Property expression.
public protocol PropertyExpressionProtocol: ExpressionProtocol {
    
    /// Specifies an alias name of the data source to query the data from.
    ///
    /// - Parameter alias: The alias name of the data source.
    /// - Returns: The property expression with the given data source alias name.
    func from(_ alias: String?) -> ExpressionProtocol
    
}

/* internal */ class PropertyExpression: QueryExpression, PropertyExpressionProtocol {

    public func from(_ alias: String?) -> ExpressionProtocol {
        if let prop = self.property {
            return QueryExpression(CBLQueryExpression.property(prop, from: alias))
        } else {
            return QueryExpression(CBLQueryExpression.all(from: alias))
        }
    }
    
    // Internal
    
    let property: String?
    
    init(property: String?) {
        self.property = property
        if let prop = property {
            super.init(CBLQueryExpression.property(prop))
        } else {
            super.init(CBLQueryExpression.all())
        }
    }
    
}
