//
//  DocumentFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// DocumentFragment provides access to a document object. DocumentFragment also provides
/// subscript access by either key or index to the data values of the document which are
/// wrapped by Fragment objects.
public class DocumentFragment: DictionaryFragment {
    
    /// Checks whether the document exists in the database or not.
    public var exists: Bool {
        return _impl.exists
    }
    
    
    /// Gets the document from the document fragment object.
    public var document: Document? {
        if let docImpl = _impl.document {
            return Document(docImpl)
        }
        return nil
    }
    
    
    // MARK: Subscript
    
    
    /// Subscript access to a Fragment object by the given key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> Fragment {
        return Fragment(_impl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLMutableDocumentFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLMutableDocumentFragment
    
}
