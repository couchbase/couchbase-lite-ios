//
//  Meta.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// Meta expression.
public protocol MetaExpressionProtocol: ExpressionProtocol {
    /// Specifies an alias name of the data source to query the data from. */
    ///
    /// - Parameter alias: The data source alias name.
    /// - Returns: The Meta expression with the given alias name specified.
    func from(_ alias: String) -> ExpressionProtocol
}

/// Meta is a factory class for creating the meta expressions that refer to
/// the metadata properties of the document.
public final class Meta {
    
    /// A metadata expression refering to the ID of the document.
    public static var id: MetaExpressionProtocol {
        return MetaExpression(type: .id)
    }
    
    
    /// A metadata expression refering to the sequence number of the document.
    /// The sequence number indicates how recently the document has been changed. If one document's
    /// `sequence` is greater than another's, that means it was changed more recently.
    public static var sequence: MetaExpressionProtocol {
        return MetaExpression(type: .sequence)
    }
    
    
    /// A metadata expression referring to the deleted boolean flag of the document.
    public static var isDeleted: MetaExpressionProtocol {
        return MetaExpression(type: .isDeleted)
    }
}

/* internal */ enum MetaType {
    case id, sequence, isDeleted
}

/* internal */ class MetaExpression: QueryExpression, MetaExpressionProtocol {
    
    /// Specifies an alias name of the data source to query the data from. */
    ///
    /// - Parameter alias: The data source alias name.
    /// - Returns: The Meta expression with the given alias name specified.
    public func from(_ alias: String) -> ExpressionProtocol {
        return QueryExpression(MetaExpression.toImpl(type: self.type, from: alias))
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
        case .isDeleted:
            return CBLQueryMeta.isDeleted(from: from)
        }
    }
    
}
