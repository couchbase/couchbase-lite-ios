//
//  ArrayExpressionIn.swift
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


/// The In class represents the IN clause object in a quantified operator (ANY/ANY AND EVERY/EVERY
/// <variable name> IN <expr> SATISFIES <expr>). The IN clause is used for specifying an array
/// object or an expression evaluated as an array object, each item of which will be evaluated
/// against the satisfies expression.
public final class ArrayExpressionIn {
    
    /// Creates a Satisfies clause object with the given IN clause expression that could be an
    /// array object or an expression evaluated as an array object.
    ///
    /// - Parameter expression: The array object or the expression evaluated as an array object.
    /// - Returns: A Satisfies object.
    public func `in`(_ expression: ExpressionProtocol) -> ArrayExpressionSatisfies {
        return ArrayExpressionSatisfies(type: self.type, variable: self.variable, inExpression: expression)
    }
    
    // MARK: Internal
    
    let type: QuantifiesType
    
    let variable: VariableExpressionProtocol
    
    init(type: QuantifiesType, variable: VariableExpressionProtocol) {
        self.type = type
        self.variable = variable
    }

}
