//
//  Document.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** A Couchbase Lite document.
    A document has key/value properties like a Dictionary; their API is defined by the
    superclass Properties. To learn how to work with properties, see that class's documentation. */
public class Document : ReadOnlyDocument, DictionaryProtocol {
    public convenience init() {
        self.init(CBLDocument())
    }
    
    
    public convenience init(_ id: String?) {
        self.init(CBLDocument(id: id))
    }
    
    
    public convenience init(dictionary: Dictionary<String, Any>?) {
        self.init(CBLDocument())
        setDictionary(dictionary)
    }
    
    
    public convenience init(_ id: String?, dictionary: Dictionary<String, Any>?) {
        self.init(CBLDocument(id: id))
        setDictionary(dictionary)
    }
    
    
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        docImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    @discardableResult public func set(_ value: Any?, forKey key: String) -> Self {
        docImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    public override func getArray(_ key: String) -> ArrayObject? {
        return getValue(key) as? ArrayObject
    }
    
    
    public override func getDictionary(_ key: String) -> DictionaryObject? {
        return getValue(key) as? DictionaryObject
    }
    
    
    /** Equal to operator for comparing two Documents object. */
    public static func == (doc1: Document, doc: Document) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: DictionaryFragment
    
    
    public override subscript(key: String) -> Fragment {
        return Fragment(docImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLDocument) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var docImpl: CBLDocument {
        return _impl as! CBLDocument
    }
}

public typealias Blob = CBLBlob
