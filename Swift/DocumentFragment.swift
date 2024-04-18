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
import CouchbaseLiteSwift_Private

/// DocumentFragment provides access to a document object. DocumentFragment also provides
/// subscript access by either key or index to the data values of the document which are
/// wrapped by Fragment objects.
public final class DocumentFragment: DictionaryFragment {
    
    /// Checks whether the document exists in the database or not.
    public var exists: Bool {
        return impl.exists
    }
    
    /// Gets the document from the document fragment object.
    public var document: Document? {
        if let docImpl = impl.document {
            return Document(docImpl, collection: collection)
        }
        return nil
    }
    
    // MARK: Subscript
    
    /// Subscript access to a Fragment object by the given key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> Fragment {
        return Fragment((impl as CBLDictionaryFragment)[key])
    }
    
    // MARK: Internal
    
    init(_ impl: CBLDocumentFragment, collection: Collection) {
        self.impl = impl
        self.collection = collection
    }
    
    let impl: CBLDocumentFragment
    let collection: Collection
    
}
