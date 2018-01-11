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
    public static func negated(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.negated(toImpl(expression)))
    }
    
    
    /// Creates a negated expression representing the negated result of the given expression.
    ///
    /// - Parameter expression: The expression to be negated.
    /// - Returns: A negated expression
    public static func not(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.not(toImpl(expression)))
    }
    
    
    // MARK: Arithmetic Operators
    
    
    /// Creates a multiply expression to multiply the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be multipled by.
    /// - Returns: A multiply expression.
    public func multiply(_ expression: Any) -> Expression {
        return Expression(self.impl.multiply(Expression.toImpl(expression)))
    }
    
    
    /// Creates a divide expression to divide the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be devided by.
    /// - Returns: A divide expression.
    public func divide(_ expression: Any) -> Expression {
        return Expression(self.impl.divide(Expression.toImpl(expression)))
    }
    
    
    /// Creates a modulo expression to modulo the current expression by the given expression.
    ///
    /// - Parameter expression: The expression to be moduloed by.
    /// - Returns: A modulo expression.
    public func modulo(_ expression: Any) -> Expression {
        return Expression(self.impl.modulo(Expression.toImpl(expression)))
    }

    
    /// Creates an add expression to add the given expression to the current expression.
    ///
    /// - Parameter expression: The expression to add to the current expression.
    /// - Returns: An add expression.
    public func add(_ expression: Any) -> Expression {
        return Expression(self.impl.add(Expression.toImpl(expression)))
    }

    
    /// Creates a subtract expression to subtract the given expression from the current expression.
    ///
    /// - Parameter expression: The expression to substract from the current expression.
    /// - Returns: A subtract expression.
    public func subtract(_ expression: Any) -> Expression {
        return Expression(self.impl.subtract(Expression.toImpl(expression)))
    }
    
    
    // MARK: Comparison Operators
    
    
    /// Creates a less than expression that evaluates whether or not the current expression
    /// is less than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than expression.
    public func lessThan(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThan(Expression.toImpl(expression)))
    }
    
    
    /// Creates a less than or equal to expression that evaluates whether or not the current
    /// expression is less than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A less than or equal to expression.
    public func lessThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThanOrEqual(to: Expression.toImpl(expression)))
    }
    

    /// Creates a greater than expression that evaluates whether or not the current expression
    /// is greater than the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than expression.
    public func greaterThan(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThan(Expression.toImpl(expression)))
    }
    
    
    /// Creates a greater than or equal to expression that evaluates whether or not the current
    /// expression is greater than or equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A greater than or equal to expression.
    public func greaterThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThanOrEqual(to: Expression.toImpl(expression)))
    }
    
    
    /// Creates an equal to expression that evaluates whether or not the current expression is equal
    /// to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An equal to expression.
    public func equalTo(_ expression: Any) -> Expression {
        return Expression(self.impl.equal(to: Expression.toImpl(expression)))
    }
    
    
    /// Creates a NOT equal to expression that evaluates whether or not the current expression
    /// is not equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A NOT equal to expression.
    public func notEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notEqual(to: Expression.toImpl(expression)))
    }
    
    
    // MARK: Like operators

    
    /// Creates a Like expression that evaluates whether or not the current expression is LIKE
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A Like expression.
    public func like(_ expression: Any) -> Expression {
        return Expression(self.impl.like(Expression.toImpl(expression)))
    }
    
    
    // MARK: Regex operators

    
    /// Creates a regex match expression that evaluates whether or not the current expression
    /// regex matches the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: A regex match expression.
    public func regex(_ expression: Any) -> Expression {
        return Expression(self.impl.regex(Expression.toImpl(expression)))
    }

    
    /// Creates an IS expression that evaluates whether or not the current expression is equal to
    /// the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS expression.
    public func `is`(_ expression: Any) -> Expression {
        return Expression(self.impl.is(Expression.toImpl(expression)))
    }
    
    
    /// Creates an IS NOT expression that evaluates whether or not the current expression is not
    /// equal to the given expression.
    ///
    /// - Parameter expression: The expression to be compared with the current expression.
    /// - Returns: An IS NOT expression.
    public func isNot(_ expression: Any) -> Expression {
        return Expression(self.impl.isNot(to: Expression.toImpl(expression)))
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
    public func and(_ expression: Any) -> Expression {
        return Expression(self.impl.andExpression(Expression.toImpl(expression)))
    }
    
    
    /// Creates a logical OR expression that performs logical OR operation with the current
    /// expression.
    ///
    /// - Parameter expression: The expression to OR with the current expression.
    /// - Returns: A logical OR Expression.
    public func or(_ expression: Any) -> Expression {
        return Expression(self.impl.orExpression(Expression.toImpl(expression)))
    }
    
    // MARK: Aggregate operators
    
    
    /// Creates a between expression that evaluates whether or not the current expression is
    /// between the given expressions inclusively.
    ///
    /// - Parameters:
    ///   - expression1: The inclusive lower bound expression.
    ///   - expression2: The inclusive upper bound expression.
    /// - Returns: A BETWEEN expression.
    public func between(_ expression1: Any, and expression2: Any) -> Expression {
        return Expression(self.impl.between(Expression.toImpl(expression1),
                                                   and: Expression.toImpl(expression2)))
    }

    
    // MARK: Collection operators:
    
    
    /// Creates an IN expression that evaluates whether or not the current expression is in the
    /// given expressions.
    ///
    /// - Parameter expressions: The expression array to be evaluated with.
    /// - Returns: An IN exprssion.
    public func `in`(_ expressions: [Any]) -> Expression {
        var impls: [Any] = []
        for exp in expressions {
            impls.append(Expression.toImpl(exp))
        }
        return Expression(self.impl.in(impls))
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
    
    static func toImpl(_ expression: Any) -> Any {
        var exp: Any
        if let xexp = expression as? Expression {
            exp = xexp.impl
        } else {
            exp = expression
        }
        return exp
    }
    
    static func toImpl(expressions: [Expression]) -> [CBLQueryExpression] {
        var impls: [CBLQueryExpression] = []
        for expr in expressions {
            impls.append(expr.impl)
        }
        return impls;
    }
    
}


extension Expression: CustomStringConvertible {
    
    public var description: String {
        return "\(type(of: self))[\(self.impl.description)]"
    }
    
}
