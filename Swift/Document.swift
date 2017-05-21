//
//  Document.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Couchbase Lite document.
/// A document has key/value properties like a Dictionary; their API is defined by the
/// superclass Properties. To learn how to work with properties, see that class's documentation.
public class Document : ReadOnlyDocument, DictionaryProtocol {
    /// Initializes a new Document object with a new random UUID. The created document will be
    /// saved into a database when you call the Database's save() method with the document
    /// object given.
    public convenience init() {
        self.init(CBLDocument())
    }

    
    /// Initializes a new Document object with the given ID. If a nil ID value is given, 
    /// the document will be created with a new random UUID. The created document will be saved 
    /// into a database when you call the Database's save() method with the document object given.
    /// - Parameter id: the document ID.
    public convenience init(_ id: String?) {
        self.init(CBLDocument(id: id))
    }
    
    
    /// Initializes a new Document object with a new random UUID and the dictionary as the content.
    /// Allowed dictionary value types are Array, Date, Dictionary, Number, NSNull, String,
    /// ArrayObject, Blob, DictionaryObject. The Arrays and Dictionaries must contain only
    /// the above types. The created document will be saved into a database when you call the
    /// Database's save() method with the document object given.
    /// - Parameter dictionary: the dictionary object.
    public convenience init(dictionary: Dictionary<String, Any>?) {
        self.init(CBLDocument())
        setDictionary(dictionary)
    }
    
    
    /// Initializes a new Document object with a given ID and the dictionary as the content.
    /// If a nil ID value is given, the document will be created with a new random UUID.
    /// Allowed dictionary value types are Array, Date, Dictionary, Number, NSNull, String,
    /// ArrayObject, Blob, DictionaryObject. The Arrays and Dictionaries must contain only
    /// the above types. The created document will be saved into a database when you call the
    /// Database's save() method with the document object given.
    /// - Parameter id: the document ID.
    /// - Parameter dictionary: the dictionary object.
    public convenience init(_ id: String?, dictionary: Dictionary<String, Any>?) {
        self.init(CBLDocument(id: id))
        setDictionary(dictionary)
    }
    
    
    /// Set a dictionary as a content. Allowed value types are Array, Date, Dictionary,
    /// Number, NSNull, String, ArrayObject, Blob, DictionaryObject. The Arrays and
    /// Dictionaries must contain only the above types. Setting the new dictionary content
    /// will replace the current data including the existing ArrayObject and DictionaryObject
    /// objects.
    /// - Parameter dictionary: the dictionary.
    /// - Returns: the Document object.
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        docImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    /// Set an object value by key. Setting the value to nil will remove the property.
    /// Allowed value types are Array, Date, Dictionary, Number, NSNull, String, ArrayObject,
    /// Blob, DictionaryObject. The Arrays and Dictionaries must contain only the above types.
    /// An Date object will be converted to an ISO-8601 format string.
    /// - Parameter value: the object value.
    /// - Returns: the Document object.
    @discardableResult public func set(_ value: Any?, forKey key: String) -> Self {
        docImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    @discardableResult public func remove(forKey key: String) -> Self {
        docImpl.removeObject(forKey: key)
        return self
    }
    
    
    /// Get a property's value as an ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    /// - Parameter key: the key.
    /// - Returns: the ArrayObject object or nil if the property doesn't exist.
    public override func array(forKey key: String) -> ArrayObject? {
        return value(forKey: key) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    /// - Parameter key: the key.
    /// - Returns: the DictionaryObject object or nil if the key doesn't exist.
    public override func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    
    /// Equal to operator for comparing two Documents object.
    public static func == (doc1: Document, doc: Document) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: DictionaryFragment
    
    
    /// Subscripting access to a Fragment object that represents the value of the dictionary
    /// by key.
    /// - Parameter key: the key.
    /// - Returns: the Fragment object.
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
