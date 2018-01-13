//
//  VariableExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 1/13/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

import Foundation


/// Variable Expression used for expressing an array item
/// in the ArrayExpression.
public final class VariableExpression: Expression {
    
    // MARK: Internal
    
    init(name: String) {
        super.init(CBLQueryArrayExpression.variable(withName: name))
    }
}
