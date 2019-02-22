//
//  DocumentFragment.swift
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


/// DocumentFragment provides access to a document object. DocumentFragment also provides
/// subscript access by either key or index to the data values of the document which are
/// wrapped by Fragment objects.
public final class DocumentFragment: DictionaryFragment {
    
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
    
    
    init(_ impl: CBLDocumentFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLDocumentFragment
    
}
