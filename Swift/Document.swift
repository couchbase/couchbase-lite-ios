//
//  Document.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Couchbase Lite document.
public class Document : ReadOnlyDocument, DictionaryProtocol {
    
    // MARK: Initializers
    
    
    /// Initializes a new Document object with a new random UUID. The created document will be
    /// saved into a database when you call the Database's save() method with the document
    /// object given.
    public convenience init() {
        self.init(CBLDocument())
    }

    
    /// Initializes a new Document object with the given ID. If a nil ID value is given,
    /// the document will be created with a new random UUID. The created document will be saved
    /// into a database when you call the Database's save() method with the document object given.
    ///
    /// - Parameter id: The document ID.
    public convenience init(_ id: String?) {
        self.init(CBLDocument(id: id))
    }
    
    
    /// Initializes a new Document object with a new random UUID and the dictionary as the content.
    /// Allowed dictionary value types are Array, Date, Dictionary, Number, NSNull, String,
    /// ArrayObject, Blob, DictionaryObject. The Arrays and Dictionaries must contain only
    /// the above types. The created document will be saved into a database when you call the
    /// Database's save() method with the document object given.
    ///
    /// - Parameter dictionary: The dictionary object.
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
    ///
    /// - Parameters:
    ///   - id: The document ID.
    ///   - dictionary: The dictionary object.
    public convenience init(_ id: String?, dictionary: Dictionary<String, Any>?) {
        self.init(CBLDocument(id: id))
        setDictionary(dictionary)
    }
    
    
    // MARK: Type Setters
    
    
    /// Set an ArrayObject object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The ArrayObject object.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setArray(_ value: ArrayObject?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a Blob object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Blob object
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setBlob(_ value: Blob?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a boolean value for the given key.
    ///
    /// - Parameters:
    ///   - value: The boolean value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setBoolean(_ value: Bool, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a Date object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Date object.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setDate(_ value: Date?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a DictionaryObject object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The DictionaryObject object.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setDictionary(_ value: DictionaryObject?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a double value for the given key.
    ///
    /// - Parameters:
    ///   - value: The double value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setDouble(_ value: Double, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a float value for the given key.
    ///
    /// - Parameters:
    ///   - value: The float value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setFloat(_ value: Float, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set an integer value for the given key.
    ///
    /// - Parameters:
    ///   - value: The integer value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setInteger(_ value: Int, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a String value for the given key.
    ///
    /// - Parameters:
    ///   - value: The String value.
    ///   - key: The Document object.
    /// - Returns: The Document object.
    @discardableResult public func setString(_ value: String?, forKey key: String) -> Self {
        return setValue(value, forKey:  key)
    }
    
    
    /// Set a value for the given key. Allowed value types are Array, Date, Dictionary,
    /// Number types, NSNull, String, ArrayObject, Blob, DictionaryObject and nil.
    /// The Arrays and Dictionaries must contain only the above types. A nil value will be
    /// converted to an NSNull. An Date object will be converted to an ISO-8601 format string.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setValue(_ value: Any?, forKey key: String) -> Self {
        docImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    // MARK: Setting content with a Dictionary
    
    
    /// Set a dictionary as a content. Allowed value types are Array, Date, Dictionary,
    /// Number, NSNull, String, ArrayObject, Blob, DictionaryObject. The Arrays and
    /// Dictionaries must contain only the above types. Setting the new dictionary content
    /// will replace the current data including the existing ArrayObject and DictionaryObject
    /// objects.
    ///
    /// - Parameter dictionary: The dictionary.
    /// - Returns: The Document object.
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        docImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    // MARK: Removing Entries
    
    
    /// Removes a given key and its value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Document object.
    @discardableResult public func remove(forKey key: String) -> Self {
        docImpl.removeObject(forKey: key)
        return self
    }
    
    
    // MARK: Getting DictionaryObject and ArrayObject
    
    
    /// Get a property's value as an ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The ArrayObject object or nil if the property doesn't exist.
    public override func array(forKey key: String) -> ArrayObject? {
        return value(forKey: key) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: The DictionaryObject object or nil if the key doesn't exist.
    public override func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    
    // MARK: Operators
    
    
    /// Equal to operator for comparing two Documents object.
    public static func == (doc1: Document, doc: Document) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: Subscript
    
    
    /// Subscripting access to a Fragment object that represents the value of the dictionary by key.
    ///
    /// - Parameter key: The key.
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
