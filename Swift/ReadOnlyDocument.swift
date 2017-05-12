//
//  ReadOnlyDocument.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public class ReadOnlyDocument : ReadOnlyDictionaryObject {
    
    /** The document's ID. */
    public var id: String {
        return self.impl.documentID
    }
    
    
    /** Sequence number of the document in the database.
     This indicates how recently the document has been changed: every time any document is updated,
     the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
     property changes that means it's been changed (on-disk); and if one document's `sequence`
     is greater than another's, that means it was changed more recently. */
    public var sequence: UInt64 {
        return self.impl.sequence
    }
    
    
    /** Is the document deleted? */
    public var isDeleted: Bool {
        return self.impl.isDeleted
    }
    
    
    /** Equal to operator for comparing two ReadOnlyDocument object. */
    public static func == (doc1: ReadOnlyDocument, doc: ReadOnlyDocument) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyDocument) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    private var impl: CBLReadOnlyDocument {
        return _impl as! CBLReadOnlyDocument
    }
}
