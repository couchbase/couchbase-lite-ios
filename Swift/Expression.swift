//
//  Expression.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// An Expression represents an expression used for constructing a query statement.
public class Expression {
    
    // MARK: Property
    
    
    /// Creates a property expression representing the value of the given property name.
    ///
    /// - Parameter property: The property name in the key path format.
    /// - Returns: A property expression.
    public static func property(_ property: String) -> PropertyExpression {
        return PropertyExpression(property: property)
    }
    
    
    /// Creates a star expression.
    ///
    /// - Returns: A star expression.
    public static func all() -> PropertyExpression {
        return PropertyExpression(property: "")
    }
    
    
    // MARK: Value
    
    
    /// Creates a value expression. The supported value types are String,
    /// NSNumber, int, int64, float, double, boolean, Date and null.
    ///
    /// - Parameter value: The value.
    /// - Returns: The value expression.
    public static func value(_ value: Any?) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a string expression.
    ///
    /// - Parameter value: The string value.
    /// - Returns: The string expression.
    public static func string(_ value: String?) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a number expression.
    ///
    /// - Parameter value: The number value.
    /// - Returns: The number expression.
    public static func number(_ value: NSNumber?) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates an integer expression.
    ///
    /// - Parameter value: The integer value.
    /// - Returns: The integer expression.
    public static func int(_ value: Int) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a 64-bit integer expression.
    ///
    /// - Parameter value: The 64-bit integer value.
    /// - Returns: The 64-bit integer expression.
    public static func int64(_ value: Int64) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a float expression.
    ///
    /// - Parameter value: The float value.
    /// - Returns: The float expression.
    public static func float(_ value: Float) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a double expression.
    ///
    /// - Parameter value: The double value.
    /// - Returns: The double expression.
    public static func double(_ value: Double) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a boolean expression.
    ///
    /// - Parameter value: The boolean value.
    /// - Returns: The boolean expression.
    public static func boolean(_ value: Bool) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    /// Creates a date expression.
    ///
    /// - Parameter value: The date value.
    /// - Returns: The date expression.
    public static func date(_ value: Date?) -> Expression {
        return ValueExpression(value: value)
    }
    
    
    // MARK: Parameter
    
    
    /// Creates a parameter expression with the given parameter name.
    ///
    /// - Parameter name: The parameter name
    /// - Returns:  A parameter expression.
    public static func parameter(_ name: String) -> Expression {
        return Expression(CBLQueryExpression.parameterNamed(name))
    }
    
    
    // MARK: Unary operators
    
    
    /// Creates a negated expression representing the negated result of the given expression.
    ///
    /// - Parameter expression: The expression to be negated.
    /// - Returns: A negated expression.
    public static func negated(_ expression: Expression) -> Expression {
        return Expression(CBLQueryExpression.negated(expression.impl))
    }
    
    
    /// Creates a negated expression representing the negated result of the given expression.
    ///
    /// - Parameter expression: The expression to be negated.
    /// - Returns: A negated expression
    public static func not(_ expression: Expression) -> Expression {
        return Expression(CBLQueryExpression.not(expression.impl))
    }
    
    
    // MARK: Arithmetic Operators
    
    
    /// Creates a multiply expression to multiply the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be multipled by.
    /// - Returns: A multiply expression.
    public func multiply(_ expression: Expression) -> Expression {
        return Expression(self.impl.multiply(expression.impl))
    }
    
    
    /// Creates a divide expression to divide the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be devided by.
    /// - Returns: A divide expression.
    public func divide(_ expression: Expression) -> Expression {
        return Expression(self.impl.divide(expression.impl))
    }
    
    
    /// Creates a modulo expression to modulo the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be moduloed by.
    /// - Returns: A modulo expression.
    public func modulo(_ expression: Expression) -> Expression {
        return Expression(self.impl.modulo(expression.impl))
    }

    
    /// Creates an add expression to add the given expression to the current expression.
    ///
    /// - Parameter expression: The expression to add to the current expression.
    /// - Returns: An add expression.
    public func add(_ expression: Expression) -> Expression {
        return Expression(self.impl.add(expression.impl))
    }

    
    /// Creates a subtract expression to subtract the given expression from the current expression.
    ///
    /// - Parameter expression: The expression to substract from the current expression.
    /// - Returns: A subtract expression.
    public func subtract(_ expression: Expression) -> Expression {
        return Expression(self.impl.subtract(expression.impl))
    }
    
    
    // MARK: Comparison Operators
    
    
    /// Creates a less than expression that evaluates whether or not the current expression
    /// is less than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than expression.
    public func lessThan(_ expression: Expression) -> Expression {
        return Expression(self.impl.lessThan(expression.impl))
    }
    
    
    /// Creates a less than or equal to expression that evaluates whether or not the current
    /// expression is less than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than or equal to expression.
    public func lessThanOrEqualTo(_ expression: Expression) -> Expression {
        return Expression(self.impl.lessThanOrEqual(to: expression.impl))
    }
    

    /// Creates a greater than expression that evaluates whether or not the current expression
    /// is greater than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than expression.
    public func greaterThan(_ expression: Expression) -> Expression {
        return Expression(self.impl.greaterThan(expression.impl))
    }
    
    
    /// Creates a greater than or equal to expression that evaluates whether or not the current
    /// expression is greater than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than or equal to expression.
    public func greaterThanOrEqualTo(_ expression: Expression) -> Expression {
        return Expression(self.impl.greaterThanOrEqual(to: expression.impl))
    }
    
    
    /// Creates an equal to expression that evaluates whether or not the current expression is equal
    /// to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An equal to expression.
    public func equalTo(_ expression: Expression) -> Expression {
        return Expression(self.impl.equal(to: expression.impl))
    }
    
    
    /// Creates a NOT equal to expression that evaluates whether or not the current expression
    /// is not equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A NOT equal to expression.
    public func notEqualTo(_ expression: Expression) -> Expression {
        return Expression(self.impl.notEqual(to: expression.impl))
    }
    
    
    // MARK: Like operators

    
    /// Creates a Like expression that evaluates whether or not the current expression is LIKE
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A Like expression.
    public func like(_ expression: Expression) -> Expression {
        return Expression(self.impl.like(expression.impl))
    }
    
    
    // MARK: Regex operators

    
    /// Creates a regex match expression that evaluates whether or not the current expression
    /// regex matches the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A regex match expression.
    public func regex(_ expression: Expression) -> Expression {
        return Expression(self.impl.regex(expression.impl))
    }

    
    /// Creates an IS expression that evaluates whether or not the current expression is equal to
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS expression.
    public func `is`(_ expression: Expression) -> Expression {
        return Expression(self.impl.is(expression.impl))
    }
    
    
    /// Creates an IS NOT expression that evaluates whether or not the current expression is not
    /// equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS NOT expression.
    public func isNot(_ expression: Expression) -> Expression {
        return Expression(self.impl.isNot(expression.impl))
    }
    
    
    // MARK: NULL check operators.
    
 
    /// Creates an IS NULL OR MISSING expression that evaluates whether or not the current
    /// expression is null or missing.
    ///
    /// - Returns: An IS NULL expression.
    public func isNullOrMissing() -> Expression {
        return Expression(self.impl.isNullOrMissing())
    }
    
    
    /// Creates an IS NOT NULL OR MISSING expression that evaluates whether or not the current
    /// expression is NOT null or missing.
    ///
    /// - Returns: An IS NOT NULL expression.
    public func notNullOrMissing() -> Expression {
        return Expression(self.impl.notNullOrMissing())
    }
    
    
    // MARK: Bitwise operators
    
    
    /// Creates a logical AND expression that performs logical AND operation with the current
    /// expression.
    ///
    /// - Parameter expression: The expression to AND with the current expression.
    /// - Returns: A logical AND expression.
    public func and(_ expression: Expression) -> Expression {
        return Expression(self.impl.andExpression(expression.impl))
    }
    
    
    /// Creates a logical OR expression that performs logical OR operation with the current
    /// expression.
    ///
    /// - Parameter expression: The expression to OR with the current expression.
    /// - Returns: A logical OR Expression.
    public func or(_ expression: Expression) -> Expression {
        return Expression(self.impl.orExpression(expression.impl))
    }
    
    // MARK: Aggregate operators
    
    
    /// Creates a between expression that evaluates whether or not the current expression is
    /// between the given expressions inclusively.
    ///
    /// - Parameters:
    ///   - expression1: The inclusive lower bound expression.
    ///   - expression2: The inclusive upper bound expression.
    /// - Returns: A BETWEEN expression.
    public func between(_ expression1: Expression, and expression2: Expression) -> Expression {
        return Expression(self.impl.between(expression1.impl, and: expression2.impl))
    }

    
    // MARK: Collection operators:
    
    
    /// Creates an IN expression that evaluates whether or not the current expression is in the
    /// given expressions.
    ///
    /// - Parameter expressions: The expression array to be evaluated with.
    /// - Returns: An IN exprssion.
    public func `in`(_ expressions: [Expression]) -> Expression {
        return Expression(self.impl.in(expressions.map() { $0.impl }))
    }
    
    
    // MARK: Collation
    
    
    /// Creates a Collate expression with the given Collation specification. Commonly
    /// the collate expression is used in the Order BY clause or the string comparison
    /// expression (e.g. equalTo or lessThan) to specify how the two strings are
    /// compared.
    ///
    /// - Parameter collation: The collation object.
    /// - Returns: A Collate expression.
    public func collate(_ collation: Collation) -> Expression {
        return Expression(self.impl.collate(collation.impl!))
    }
    
    
    // MARK: Internal
    
    
    let impl: CBLQueryExpression
    
    init (_ expression: CBLQueryExpression) {
        self.impl = expression
    }
    
    /*
    static func toImpl(_ expression: Any) -> Any {
        var exp: Any
        if let xexp = expression as? Expression {
            exp = xexp.impl
        } else {
            exp = expression
        }
        return exp
    }
    */
    
    static func toImpl(expressions: [Expression]) -> [CBLQueryExpression] {
        return expressions.map() { $0.impl }
    }
}


extension Expression: CustomStringConvertible {
    
    public var description: String {
        return "\(type(of: self))[\(self.impl.description)]"
    }
    
}
