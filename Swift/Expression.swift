//
//  Expression.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 3/20/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** An Expression represents an expression used for constructing a query statement. */
public final class Expression {
    
    /** Create a property keypath expression. */
    public static func property(_ property: String) -> Expression {
        return Expression(CBLQueryExpression.property(property))
    }
    
    /** Create a negated expression. */
    public static func negated(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.negated(toCBLExp(expression)))
    }
    
    /** Create a negated expression. */
    public static func not(_ expression: Any) -> Expression {
        return Expression(CBLQueryExpression.not(toCBLExp(expression)))
    }
    
    /** Create a multiply operation expression. */
    public func multiply(_ expression: Any) -> Expression {
        return Expression(self.impl.multiply(Expression.toCBLExp(expression)));
    }
    
    /** Create a divide operation expression. */
    public func divide(_ expression: Any) -> Expression {
        return Expression(self.impl.divide(Expression.toCBLExp(expression)));
    }
    
    /** Create a modulus operation expression. */
    public func modulo(_ expression: Any) -> Expression {
        return Expression(self.impl.modulo(Expression.toCBLExp(expression)));
    }
    
    /** Create an add operation expression. */
    public func add(_ expression: Any) -> Expression {
        return Expression(self.impl.add(Expression.toCBLExp(expression)));
    }
    
    /** Create an subtract operation expression. */
    public func subtract(_ expression: Any) -> Expression {
        return Expression(self.impl.subtract(Expression.toCBLExp(expression)));
    }
    
    /** Create a less than comparison expression. */
    public func lessThan(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThan(Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT less than comparison expression. */
    public func notLessThan(_ expression: Any) -> Expression {
        return Expression(self.impl.notLessThan(Expression.toCBLExp(expression)));
    }
    
    /** Create a less than or equal to comparison expression. */
    public func lessThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.lessThanOrEqual(to: Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT less than or equal to comparison expression. */
    public func notLessThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notLessThanOrEqual(to: Expression.toCBLExp(expression)));
    }
    
    /** Create a greater then comparison expression. */
    public func greaterThan(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThan(Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT greater then comparison expression. */
    public func notGreaterThan(_ expression: Any) -> Expression {
        return Expression(self.impl.notGreaterThan(Expression.toCBLExp(expression)));
    }
    
    /** Create a greather than or equal to comparison expression. */
    public func greaterThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.greaterThanOrEqual(to: Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT greather than or equal comparison expression. */
    public func notGreaterThanOrEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notGreaterThanOrEqual(to: Expression.toCBLExp(expression)));
    }
    
    /** Create an equal to comparison expression. */
    public func equalTo(_ expression: Any) -> Expression {
        return Expression(self.impl.equal(to: Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT equal to comparison expression. */
    public func notEqualTo(_ expression: Any) -> Expression {
        return Expression(self.impl.notEqual(to: Expression.toCBLExp(expression)));
    }
    
    /** Create an AND operation expression. */
    public func and(_ expression: Any) -> Expression {
        return Expression(self.impl.and(Expression.toCBLExp(expression)));
    }
    
    /** Create an OR operation expression. */
    public func or(_ expression: Any) -> Expression {
        return Expression(self.impl.or(Expression.toCBLExp(expression)));
    }
    
    /** Create a LIKE comparison expression. */
    public func like(_ expression: Any) -> Expression {
        return Expression(self.impl.like(Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT LIKE comparison expression. */
    public func notLike(_ expression: Any) -> Expression {
        return Expression(self.impl.notLike(Expression.toCBLExp(expression)));
    }
    
    /** Create a REGEX_LIKE comparison expression. */
    public func regex(_ expression: Any) -> Expression {
        return Expression(self.impl.regex(Expression.toCBLExp(expression)));
    }
    
    /** Create a NOT REGEX_LIKE comparison expression. */
    public func notRegex(_ expression: Any) -> Expression {
        return Expression(self.impl.notRegex(Expression.toCBLExp(expression)));
    }
    
    /** Create a fulltext search matching expression. */
    public func match(_ expression: Any) -> Expression {
        return Expression(self.impl.match(Expression.toCBLExp(expression)));
    }
    
    /** Create a fulltext search NOT matching expression. */
    public func notMatch(_ expression: Any) -> Expression {
        return Expression(self.impl.notMatch(Expression.toCBLExp(expression)));
    }
    
    /** Create a null check expression. */
    public func isNull() -> Expression {
        return Expression(self.impl.isNull());
    }
    
    /** Create a NOT null check expression. */
    public func notNull() -> Expression {
        return Expression(self.impl.notNull());
    }
    
    /** Create an is comparsion expression. The is comparison is the same as an equal to comparison. */
    public func `is`(_ expression: Any) -> Expression {
        return Expression(self.impl.is(Expression.toCBLExp(expression)));
    }
    
    /** Create an is NOT comparsion expression. */
    public func isNot(_ expression: Any) -> Expression {
        return Expression(self.impl.isNot(to: Expression.toCBLExp(expression)));
    }
    
    /** Create a between expression. */
    public func between(_ expression1: Any, and expression2: Any) -> Expression {
        return Expression(self.impl.between(Expression.toCBLExp(expression1),
                                                   and: Expression.toCBLExp(expression2)));
    }
    
    /** Create a NOT between expression. */
    public func notBetween(_ expression1: Any, and expression2: Any) -> Expression {
        return Expression(self.impl.notBetween(Expression.toCBLExp(expression1),
                                                      and: Expression.toCBLExp(expression2)));
    }
    
    let impl: CBLQueryExpression
    
    init (_ expression: CBLQueryExpression) {
        self.impl = expression
    }
    
    static func toCBLExp(_ expression: Any) -> Any {
        var exp: Any
        if let xexp = expression as? Expression {
            exp = xexp.impl
        } else {
            exp = expression
        }
        return exp
    }
    
}
