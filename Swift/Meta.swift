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
public final class Meta {
    
    /// A metadata expression refering to the ID of the document.
    public static var id: MetaExpression {
        return MetaExpression(type: .id)
    }
    
    
    /// A metadata expression refering to the sequence number of the document.
    /// The sequence number indicates how recently the document has been changed. If one document's
    /// `sequence` is greater than another's, that means it was changed more recently.
    public static var sequence: MetaExpression {
        return MetaExpression(type: .sequence)
    }
}

/* internal */ enum MetaType {
    case id, sequence
}
