//
//  Function.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Function represents a function expression. */
public class Function: Expression {
    /** Create an AVG() function expression that returns the average of all the number values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The average value. */
    public static func avg(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.avg(toCBLExp(expression)))
    }
    
    /** Create a COUNT() function expression that returns the count of all values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The count value. */
    public static func count(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.count(toCBLExp(expression)))
    }
    
    /** Create a MIN() function expression that returns the minimum value
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The minimum value. */
    public static func min(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.min(toCBLExp(expression)))
    }
    
    /** Create a MAX() function expression that returns the maximum value
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The maximum value. */
    public static func max(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.max(toCBLExp(expression)))
    }
    
    /** Create a SUM() function expression that return the sum of all number values
        in the group of the values expressed by the given expression.
        @param expression   The expression.
        @return The sum value. */
    public static func sum(_ expression: Any) -> Expression {
        return Expression(CBLQueryFunction.sum(toCBLExp(expression)))
    }
}
