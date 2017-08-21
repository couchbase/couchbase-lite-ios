//
//  Meta.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// Meta is a factory class for creating the expressions that refer to
/// the metadata properties of the document.
public class Meta {
    
    /// A metadata expression refering to the ID of the document.
    public var id: MetaExpression {
        return MetaExpression(type: .id)
    }
    
    
    /// A metadata expression refering to the sequence number of the document.
    /// The sequence number indicates how recently the document has been changed. If one document's
    /// `sequence` is greater than another's, that means it was changed more recently.
    public var sequence: MetaExpression {
        return MetaExpression(type: .sequence)
    }
}

/* internal */ enum MetaType {
    case id, sequence
}


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
            return CBLQueryExpression.meta(from: from).id
        case .sequence:
            return CBLQueryExpression.meta(from: from).sequence
        }
    }
    
}
