//
//  Expression.swift
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

/// Query expression.
public protocol ExpressionProtocol {
    
    // MARK: Arithmetic operators
    
    /// Creates a multiply expression to multiply the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be multipled by.
    /// - Returns: A multiply expression.
    func multiply(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a divide expression to divide the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be devided by.
    /// - Returns: A divide expression.
    func divide(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a modulo expression to modulo the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be moduloed by.
    /// - Returns: A modulo expression.
    func modulo(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates an add expression to add the given expression to the current expression.
    ///
    /// - Parameter expression: The expression to add to the current expression.
    /// - Returns: An add expression.
    func add(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a subtract expression to subtract the given expression from the current expression.
    ///
    /// - Parameter expression: The expression to substract from the current expression.
    /// - Returns: A subtract expression.
    func subtract(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: Comparison operators
    
    /// Creates a less than expression that evaluates whether or not the current expression
    /// is less than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than expression.
    func lessThan(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a less than or equal to expression that evaluates whether or not the current
    /// expression is less than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than or equal to expression.
    func lessThanOrEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a greater than expression that evaluates whether or not the current expression
    /// is greater than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than expression.
    func greaterThan(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a greater than or equal to expression that evaluates whether or not the current
    /// expression is greater than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than or equal to expression.
    func greaterThanOrEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates an equal to expression that evaluates whether or not the current expression is equal
    /// to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An equal to expression.
    func equalTo(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a NOT equal to expression that evaluates whether or not the current expression
    /// is not equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A NOT equal to expression.
    func notEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: Like operators
    
    /// Creates a Like expression that evaluates whether or not the current expression is LIKE
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A Like expression.
    func like(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: Regex operators
    
    /// Creates a regex match expression that evaluates whether or not the current expression
    /// regex matches the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A regex match expression.
    func regex(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: IS operators
    
    /// Creates an IS expression that evaluates whether or not the current expression is equal to
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS expression.
    func `is`(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates an IS NOT expression that evaluates whether or not the current expression is not
    /// equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS NOT expression.
    func isNot(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: NULL check operators.
    
    /// Creates an IS NULL OR MISSING expression that evaluates whether or not the current
    /// expression is null or missing.
    ///
    /// - Returns: An IS NULL expression.
    func isNullOrMissing() -> ExpressionProtocol
    
    /// Creates an IS NOT NULL OR MISSING expression that evaluates whether or not the current
    /// expression is NOT null or missing.
    ///
    /// - Returns: An IS NOT NULL expression.
    func notNullOrMissing() -> ExpressionProtocol
    
    // MARK: Bitwise operators
    
    /// Creates a logical AND expression that performs logical AND operation with the current
    /// expression.
    ///
    /// - Parameter expression: The expression to AND with the current expression.
    /// - Returns: A logical AND expression.
    func and(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    /// Creates a logical OR expression that performs logical OR operation with the current
    /// expression.
    ///
    /// - Parameter expression: The expression to OR with the current expression.
    /// - Returns: A logical OR Expression.
    func or(_ expression: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: Aggregate operators
    
    /// Creates a between expression that evaluates whether or not the current expression is
    /// between the given expressions inclusively.
    ///
    /// - Parameters:
    ///   - expression1: The inclusive lower bound expression.
    ///   - expression2: The inclusive upper bound expression.
    /// - Returns: A BETWEEN expression.
    func between(_ expression1: ExpressionProtocol, and expression2: ExpressionProtocol) -> ExpressionProtocol
    
    // MARK: Collection operators:
    
    /// Creates an IN expression that evaluates whether or not the current expression is in the
    /// given expressions.
    ///
    /// - Parameter expressions: The expression array to be evaluated with.
    /// - Returns: An IN exprssion.
    func `in`(_ expressions: [ExpressionProtocol]) -> ExpressionProtocol
    
    // MARK: Collation
    
    /// Creates a Collate expression with the given Collation specification. Commonly
    /// the collate expression is used in the Order BY clause or the string comparison
    /// expression (e.g. equalTo or lessThan) to specify how the two strings are
    /// compared.
    ///
    /// - Parameter collation: The collation object.
    /// - Returns: A Collate expression.
    func collate(_ collation: CollationProtocol) -> ExpressionProtocol
    
}


/// Query expression factory.
public final class Expression {
    
    // MARK: Property
    
    /// Creates a property expression representing the value of the given property name.
    ///
    /// - Parameter property: The property name in the key path format.
    /// - Returns: A property expression.
    public static func property(_ property: String) -> PropertyExpressionProtocol {
        return PropertyExpression(property: property)
    }
    
    /// Creates a star expression.
    ///
    /// - Returns: A star expression.
    public static func all() -> PropertyExpressionProtocol {
        return PropertyExpression(property: nil)
    }
    
    // MARK: Value
    
    /// Creates a value expression. The supported value types are String,
    /// NSNumber, int, int64, float, double, boolean, Date and null.
    ///
    /// - Parameter value: The value.
    /// - Returns: The value expression.
    public static func value(_ value: Any?) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a string expression.
    ///
    /// - Parameter value: The string value.
    /// - Returns: The string expression.
    public static func string(_ value: String?) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a number expression.
    ///
    /// - Parameter value: The number value.
    /// - Returns: The number expression.
    public static func number(_ value: NSNumber?) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates an integer expression.
    ///
    /// - Parameter value: The integer value.
    /// - Returns: The integer expression.
    public static func int(_ value: Int) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a 64-bit integer expression.
    ///
    /// - Parameter value: The 64-bit integer value.
    /// - Returns: The 64-bit integer expression.
    public static func int64(_ value: Int64) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a float expression.
    ///
    /// - Parameter value: The float value.
    /// - Returns: The float expression.
    public static func float(_ value: Float) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a double expression.
    ///
    /// - Parameter value: The double value.
    /// - Returns: The double expression.
    public static func double(_ value: Double) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a boolean expression.
    ///
    /// - Parameter value: The boolean value.
    /// - Returns: The boolean expression.
    public static func boolean(_ value: Bool) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    /// Creates a date expression.
    ///
    /// - Parameter value: The date value.
    /// - Returns: The date expression.
    public static func date(_ value: Date?) -> ExpressionProtocol {
        return ValueExpression(value: value)
    }
    
    // MARK: Parameter
    
    /// Creates a parameter expression with the given parameter name.
    ///
    /// - Parameter name: The parameter name
    /// - Returns:  A parameter expression.
    public static func parameter(_ name: String) -> ExpressionProtocol {
        return QueryExpression(CBLQueryExpression.parameterNamed(name))
    }
    
    // MARK: Unary operators
    
    /// Creates a negated expression representing the negated result of the given expression.
    ///
    /// - Parameter expression: The expression to be negated.
    /// - Returns: A negated expression.
    public static func negated(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryExpression.negated(expression.toImpl()))
    }
    
    /// Creates a negated expression representing the negated result of the given expression.
    ///
    /// If the operand isn't a boolean type, it gets coerced to a boolean. The number 0 is coerced to false,
    /// the number 1 is coerced to `true`, strings are coerced to `false` (but strings prefixed with a number
    /// are coerced to `true`, for example "2willowroad@nationaltrust.org.uk").
    ///
    /// - Parameter expression: The expression to be negated.
    /// - Returns: A negated expression
    public static func not(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(CBLQueryExpression.not(expression.toImpl()))
    }
    
}

/* internal */ class QueryExpression: ExpressionProtocol, CustomStringConvertible {
    
    // MARK: Arithmetic operators
    
    /// Creates a multiply expression to multiply the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be multipled by.
    /// - Returns: A multiply expression.
    public func multiply(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.multiply(expression.toImpl()))
    }
    
    /// Creates a divide expression to divide the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be devided by.
    /// - Returns: A divide expression.
    public func divide(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.divide(expression.toImpl()))
    }
    
    /// Creates a modulo expression to modulo the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be moduloed by.
    /// - Returns: A modulo expression.
    public func modulo(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.modulo(expression.toImpl()))
    }
    
    /// Creates an add expression to add the given expression to the current expression.
    ///
    /// - Parameter expression: The expression to add to the current expression.
    /// - Returns: An add expression.
    public func add(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.add(expression.toImpl()))
    }
    
    /// Creates a subtract expression to subtract the given expression from the current expression.
    ///
    /// - Parameter expression: The expression to substract from the current expression.
    /// - Returns: A subtract expression.
    public func subtract(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.subtract(expression.toImpl()))
    }
    
    // MARK: Comparison operators
    
    /// Creates a less than expression that evaluates whether or not the current expression
    /// is less than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than expression.
    public func lessThan(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.lessThan(expression.toImpl()))
    }
    
    /// Creates a less than or equal to expression that evaluates whether or not the current
    /// expression is less than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than or equal to expression.
    public func lessThanOrEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.lessThanOrEqual(to: expression.toImpl()))
    }
    
    /// Creates a greater than expression that evaluates whether or not the current expression
    /// is greater than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than expression.
    public func greaterThan(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.greaterThan(expression.toImpl()))
    }
    
    /// Creates a greater than or equal to expression that evaluates whether or not the current
    /// expression is greater than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than or equal to expression.
    public func greaterThanOrEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.greaterThanOrEqual(to: expression.toImpl()))
    }
    
    /// Creates an equal to expression that evaluates whether or not the current expression is equal
    /// to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An equal to expression.
    public func equalTo(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.equal(to: expression.toImpl()))
    }
    
    /// Creates a NOT equal to expression that evaluates whether or not the current expression
    /// is not equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A NOT equal to expression.
    public func notEqualTo(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.notEqual(to: expression.toImpl()))
    }
    
    // MARK: Like operators
    
    /// Creates a Like expression that evaluates whether or not the current expression is LIKE
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A Like expression.
    public func like(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.like(expression.toImpl()))
    }
    
    // MARK: Regex operators
    
    /// Creates a regex match expression that evaluates whether or not the current expression
    /// regex matches the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A regex match expression.
    public func regex(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.regex(expression.toImpl()))
    }
    
    // MARK: IS operators
    
    /// Creates an IS expression that evaluates whether or not the current expression is equal to
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS expression.
    public func `is`(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.is(expression.toImpl()))
    }
    
    /// Creates an IS NOT expression that evaluates whether or not the current expression is not
    /// equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS NOT expression.
    public func isNot(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.isNot(expression.toImpl()))
    }
    
    // MARK: NULL check operators.
    
    /// Creates an IS NULL OR MISSING expression that evaluates whether or not the current
    /// expression is null or missing.
    ///
    /// - Returns: An IS NULL expression.
    public func isNullOrMissing() -> ExpressionProtocol {
        return QueryExpression(self.impl.isNullOrMissing())
    }
    
    /// Creates an IS NOT NULL OR MISSING expression that evaluates whether or not the current
    /// expression is NOT null or missing.
    ///
    /// - Returns: An IS NOT NULL expression.
    public func notNullOrMissing() -> ExpressionProtocol {
        return QueryExpression(self.impl.notNullOrMissing())
    }
    
    // MARK: Bitwise operators
    
    /// Creates a logical AND expression that performs logical AND operation with the current
    /// expression.
    ///
    /// If the operand isn't a boolean type, it gets coerced to a boolean. The number 0 is coerced to false,
    /// the number 1 is coerced to `true`, strings are coerced to `false` (but strings prefixed with a number
    /// are coerced to `true`, for example "2willowroad@nationaltrust.org.uk").
    ///
    /// - Parameter expression: The expression to AND with the current expression.
    /// - Returns: A logical AND expression.
    public func and(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.andExpression(expression.toImpl()))
    }
    
    /// Creates a logical OR expression that performs logical OR operation with the current
    /// expression.
    ///
    /// If the operand isn't a boolean type, it gets coerced to a boolean. The number 0 is coerced to false,
    /// the number 1 is coerced to `true`, strings are coerced to `false` (but strings prefixed with a number
    /// are coerced to `true`, for example "2willowroad@nationaltrust.org.uk").
    ///
    /// - Parameter expression: The expression to OR with the current expression.
    /// - Returns: A logical OR Expression.
    public func or(_ expression: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.orExpression(expression.toImpl()))
    }
    
    // MARK: Aggregate operators
    
    /// Creates a between expression that evaluates whether or not the current expression is
    /// between the given expressions inclusively.
    ///
    /// - Parameters:
    ///   - expression1: The inclusive lower bound expression.
    ///   - expression2: The inclusive upper bound expression.
    /// - Returns: A BETWEEN expression.
    public func between(_ expression1: ExpressionProtocol, and expression2: ExpressionProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.between(expression1.toImpl(), and: expression2.toImpl()))
    }
    
    // MARK: Collection operators:
    
    /// Creates an IN expression that evaluates whether or not the current expression is in the
    /// given expressions.
    ///
    /// - Parameter expressions: The expression array to be evaluated with.
    /// - Returns: An IN exprssion.
    public func `in`(_ expressions: [ExpressionProtocol]) -> ExpressionProtocol {
        return QueryExpression(self.impl.in(expressions.map() { $0.toImpl() }))
    }
    
    // MARK: Collation
    
    /// Creates a Collate expression with the given Collation specification. Commonly
    /// the collate expression is used in the Order BY clause or the string comparison
    /// expression (e.g. equalTo or lessThan) to specify how the two strings are
    /// compared.
    ///
    /// - Parameter collation: The collation object.
    /// - Returns: A Collate expression.
    public func collate(_ collation: CollationProtocol) -> ExpressionProtocol {
        return QueryExpression(self.impl.collate(collation.toImpl()))
    }
    
    // MARK: CustomStringConvertible
    
    /// Returns the string representation of the expression.
    public var description: String {
        return "\(type(of: self))[\(self.impl.description)]"
    }
    
    // MARK: Internal
    
    private let impl: CBLQueryExpression
    
    init (_ expression: CBLQueryExpression) {
        self.impl = expression
    }
    
    func toImpl() -> CBLQueryExpression {
        return impl
    }
    
    static func toImpl(expressions: [ExpressionProtocol]) -> [CBLQueryExpression] {
        return expressions.map() { $0.toImpl() }
    }
}

extension ExpressionProtocol {
    func toImpl() -> CBLQueryExpression {
        if let o = self as? QueryExpression {
            return o.toImpl()
        }
        fatalError("Unsupported expression")
    }
}

