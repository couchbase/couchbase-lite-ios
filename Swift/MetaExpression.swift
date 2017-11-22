//
//  MetaExpression.swift
//  CBL Swift
//
//  Created by Pasin Suriyentrakorn on 11/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// A meta property expression.
public class MetaExpression: Expression {
    
    /// Specifies an alias name of the data source to query the data from. */
    ///
    /// - Parameter alias: The data source alias name.
    /// - Returns: The Meta expression with the given alias name specified.
    public func from(_ alias: String) -> Expression {
        return Expression(MetaExpression.toImpl(type: self.type, from: alias))
    }
    
    // MARK: Internal
    
    let type: MetaType
    
    init(type: MetaType) {
        self.type = type
        super.init(MetaExpression.toImpl(type: type, from: nil))
    }
    
    static func toImpl(type: MetaType, from: String?) -> CBLQueryExpression {
        switch type {
        case .id:
            return CBLQueryMeta.id(from: from)
        case .sequence:
            return CBLQueryMeta.sequence(from: from)
        }
    }
    
}
