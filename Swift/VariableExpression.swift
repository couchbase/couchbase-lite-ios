//
//  VariableExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 1/13/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

import Foundation

/// Variable expression that expresses an array item in the ArrayExpression.
public protocol VariableExpressionProtocol: ExpressionProtocol {
    
}

/* internal */ class VariableExpression : QueryExpression, VariableExpressionProtocol {
    
    init(name: String) {
        super.init(CBLQueryArrayExpression.variable(withName: name))
    }
    
}
