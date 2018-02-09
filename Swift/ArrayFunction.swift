//
//  ArrayFunction.swift
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


/// Array function factory.
public final class ArrayFunction {
    
    /// Creates an ARRAY_CONTAINS(expr, value) function that checks whether the given array
    /// expression contains the given value or not.
    ///
    /// - Parameters:
    ///   - expression: The expression that evaluates to an array.
    ///   - value: The value to search for in the given array expression.
    /// - Returns: The ARRAY_CONTAINS(expr, value) function.
    public static func contains(_ expression: ExpressionProtocol, value: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryArrayFunction.contains(expression.toImpl(), value: value.toImpl()))
    }
    
    
    /// Creates an ARRAY_LENGTH(expr) function that returns the length of the given array
    /// expression.
    ///
    /// - Parameter expression: The expression that evaluates to an array.
    /// - Returns: The ARRAY_LENGTH(expr) function.
    public static func length(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryArrayFunction.length(expression.toImpl()))
    }
    
}
