//
//  ValueExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 1/13/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

import Foundation

/* internal */ class ValueExpression: Expression {
    init(value: Any?) {
        super.init(CBLQueryExpression.value(value))
    }
}
