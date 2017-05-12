//
//  DocumentFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol DocumentFragmentProtocol {
    var exists: Bool { get }
    
    var document: Document? { get }
}

public class DocumentFragment: DocumentFragmentProtocol, DictionaryFragment {
    public var exists: Bool {
        return _impl.exists
    }
    
    
    public var document: Document? {
        if let docImpl = _impl.document {
            return Document(docImpl)
        }
        return nil
    }
    
    
    // MARK: DictionaryFragment
    
    
    public subscript(key: String) -> Fragment {
        return Fragment(_impl[key])
    }
    
    
    init(_ impl: CBLDocumentFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLDocumentFragment
}
