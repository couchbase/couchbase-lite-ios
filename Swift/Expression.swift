//
//  Expression.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** An Expression represents an expression used for constructing a query statement. */
public class Expression {
    
    /** Create a property expression representing the value of the given property name.
        @param property property name in the key path format.
        @return a property expression. */
    public static func property(_ property: String) -> PropertyExpression {
        return PropertyExpression(property: property)
    }
    
    /** Create a parameter expression with the given parameter name.
        @param name The parameter name
        @return A parameter expression. */
    public static func parameter(_ name: String) -> Expression {
        return Expression(CBLQueryExpression.parameterNamed(name))
    }
    
    /** Create a negated expression representing the negated result of the given expression.
        @param expression   the expression to be negated.
        @return a negated expression. */
    public static func negated(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.negated(toImpl(expression)))
    }
    
    /** Create a negated expression representing the negated result of the given expression.
        @param expression   the expression to be negated.
        @return a negated expression */
    public static func not(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.not(toImpl(expression)))
    }
    
    /** Create a multiply expression to multiply the current expression by the given expression.
        @param expression   the expression to be multipled by.
        @return a multiply expression. */
    public func multiply(_ expression: Any) -> Expression {
        return Expression(self.impl.multiply(Expression.toImpl(expression)))
    }
    
    /** Create a divide expression to divide the current expression by the given expression.
        @param expression   the expression to be devided by.
        @return a divide expression. */
    public func divide(_ expression: Any) -> Expression {
        return Expression(self.impl.divide(Expression.toImpl(expression)))
    }
    
    /** Create a modulo expression to modulo the current expression by the given expression.
        @param expression   the expression to be moduloed by.
        @return a modulo expression. */
    public func modulo(_ expression: Any) -> Expression {
        return Expression(self.impl.modulo(Expression.toImpl(expression)))
    }
    
    /** Create an add expression to add the given expression to the current expression.
        @param expression   the expression to add to the current expression.
        @return an add expression. */
    public func add(_ expression: Any) -> Expression {
        return Expression(self.impl.add(Expression.toImpl(expression)))
    }
    
    /** Create a subtract expression to subtract the given expression from the current expression.
        @param expression   the expression to substract from the current expression.
        @return a subtract expression. */
    public func subtract(_ expression: Any) -> Expression {
        return Expression(self.impl.subtract(Expression.toImpl(expression)))
    }
    
    /** Create a less than expression that evaluates whether or not the current expression
        is less than the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a less than expression. */
    public func lessThan(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThan(Expression.toImpl(expression)))
    }
    
    /** Create a NOT less than expression that evaluates whether or not the current expression
        is not less than the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT less than expression. */
    public func notLessThan(_ expression: Any) -> Expression {
        return Expression(self.impl.notLessThan(Expression.toImpl(expression)))
    }
    
    /** Create a less than or equal to expression that evaluates whether or not the current
        expression is less than or equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a less than or equal to expression. */
    public func lessThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThanOrEqual(to: Expression.toImpl(expression)))
    }
    
    /** Create a NOT less than or equal to expression that evaluates whether or not the current
        expression is not less than or equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT less than or equal to expression. */
    public func notLessThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notLessThanOrEqual(to: Expression.toImpl(expression)))
    }
    
    /** Create a greater than expression that evaluates whether or not the current expression
        is greater than the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a greater than expression. */
    public func greaterThan(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThan(Expression.toImpl(expression)))
    }
    
    /** Create a NOT greater than expression that evaluates whether or not the current expression
        is not greater than the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT greater than expression. */
    public func notGreaterThan(_ expression: Any) -> Expression {
        return Expression(self.impl.notGreaterThan(Expression.toImpl(expression)))
    }
    
    /** Create a greater than or equal to expression that evaluates whether or not the current
        expression is greater than or equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a greater than or equal to expression. */
    public func greaterThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThanOrEqual(to: Expression.toImpl(expression)))
    }
    
    /** Create a NOT greater than or equal to expression that evaluates whether or not the current
        expression is not greater than or equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT greater than or equal to expression. */
    public func notGreaterThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notGreaterThanOrEqual(to: Expression.toImpl(expression)))
    }
    
    /** Create an equal to expression that evaluates whether or not the current expression is equal
        to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return an equal to expression. */
    public func equalTo(_ expression: Any) -> Expression {
        return Expression(self.impl.equal(to: Expression.toImpl(expression)))
    }
    
    /** Create a NOT equal to expression that evaluates whether or not the current expression
        is not equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT equal to expression. */
    public func notEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notEqual(to: Expression.toImpl(expression)))
    }
    
    /** Create a logical AND expression that performs logical AND operation with the current 
        expression.
        @param expression   the expression to AND with the current expression.
        @return a logical AND expression. */
    public func and(_ expression: Any) -> Expression {
        return Expression(self.impl.and(Expression.toImpl(expression)))
    }
    
    /** Create a logical OR expression that performs logical OR operation with the current 
        expression.
        @param expression   the expression to OR with the current expression.
        @return a logical OR Expression. */
    public func or(_ expression: Any) -> Expression {
        return Expression(self.impl.or(Expression.toImpl(expression)))
    }
    
    /** Create a Like expression that evaluates whether or not the current expression is LIKE
        the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a Like expression. */
    public func like(_ expression: Any) -> Expression {
        return Expression(self.impl.like(Expression.toImpl(expression)))
    }
    
    /** Create a NOT Like expression that evaluates whether or not the current expression is 
        NOT LIKE the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a NOT Like expression. */
    public func notLike(_ expression: Any) -> Expression {
        return Expression(self.impl.notLike(Expression.toImpl(expression)))
    }
    
    /** Create a regex match expression that evaluates whether or not the current expression
        regex matches the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a regex match expression. */
    public func regex(_ expression: Any) -> Expression {
        return Expression(self.impl.regex(Expression.toImpl(expression)))
    }
    
    /** Create a regex NOT match expression that evaluates whether or not the current expression
        regex NOT matches the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a regex NOT match expression. */
    public func notRegex(_ expression: Any) -> Expression {
        return Expression(self.impl.notRegex(Expression.toImpl(expression)))
    }
    
    /** Create a full text match expression that evaluates whether or not the current expression
        full text matches the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a full text match expression. */
    public func match(_ expression: Any) -> Expression {
        return Expression(self.impl.match(Expression.toImpl(expression)))
    }
    
    /** Create a full text NOT match expression that evaluates whether or not the current expression
        full text NOT matches the given expression.
        @param expression   the expression to be compared with the current expression.
        @return a full text NOT match expression. */
    public func notMatch(_ expression: Any) -> Expression {
        return Expression(self.impl.notMatch(Expression.toImpl(expression)))
    }
    
    /** Create an IS NULL expression that evaluates whether or not the current expression is null.
        @return an IS NULL expression. */
    public func isNull() -> Expression {
        return Expression(self.impl.isNull())
    }
    
    /** Create an IS NOT NULL expression that evaluates whether or not the current expression
        is NOT null.
        @return an IS NOT NULL expression. */
    public func notNull() -> Expression {
        return Expression(self.impl.notNull())
    }
    
    /** Create an IS expression that evaluates whether or not the current expression is equal to
        the given expression.
        @param expression   the expression to be compared with the current expression.
        @return an IS expression. */
    public func `is`(_ expression: Any) -> Expression {
        return Expression(self.impl.is(Expression.toImpl(expression)))
    }
    
    /** Create an IS NOT expression that evaluates whether or not the current expression is not 
        equal to the given expression.
        @param expression   the expression to be compared with the current expression.
        @return an IS NOT expression. */
    public func isNot(_ expression: Any) -> Expression {
        return Expression(self.impl.isNot(to: Expression.toImpl(expression)))
    }
    
    /** Create a between expression that evaluates whether or not the current expression is
        between the given expressions inclusively.
        @param expression1  the inclusive lower bound expression.
        @param expression2  the inclusive upper bound expression.
        @return a between expression. */
    public func between(_ expression1: Any, and expression2: Any) -> Expression {
        return Expression(self.impl.between(Expression.toImpl(expression1),
                                                   and: Expression.toImpl(expression2)))
    }
    
    /** Create a NOT between expression that evaluates whether or not the current expression is not
        between the given expressions inclusively.
        @param expression1  the inclusive lower bound expression.
        @param expression2  the inclusive upper bound expression.
        @return a NOT between expression. */
    public func notBetween(_ expression1: Any, and expression2: Any) -> Expression {
        return Expression(self.impl.notBetween(Expression.toImpl(expression1),
                                                      and: Expression.toImpl(expression2)))
    }
    
    /** Create an IN expression that evaluates whether or not the current expression is in the
        given expressions.
        @param  expressions the expression array to be evaluated with.
        @return an IN exprssion. */
    public func `in`(_ expressions: [Any]) -> Expression {
        var impls: [Any] = []
        for exp in expressions {
            impls.append(Expression.toImpl(exp))
        }
        return Expression(self.impl.in(impls))
    }
    
    /** Create a NOT IN expression that evaluates whether or not the current expression is not 
        in the given expressions.
        @param  expressions the expression array to be evaluated with.
        @return an IN exprssion. */
    public func notIn(_ expressions:[Any]) -> Expression {
        var impls: [Any] = []
        for exp in expressions {
            impls.append(Expression.toImpl(exp))
        }
        return Expression(self.impl.not(in: impls))
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

/** A property expression. */
public class PropertyExpression: Expression {
    let property: String
    
    init (property: String) {
        self.property = property
        super.init(CBLQueryExpression.property(property))
    }
    
    /** Specifies an alias name of the data source of the property. */
    public func from(_ alias: String) -> Expression {
        return Expression(CBLQueryExpression.property(property, from: alias))
    }
}
