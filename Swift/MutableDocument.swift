//
//  MutableDocument.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A mutable version of the Document.
public class MutableDocument : Document, MutableDictionaryProtocol {
    
    // MARK: Initializers
    
    
    /// Initializes a new Document object with a new random UUID. The created document will be
    /// saved into a database when you call the Database's save() method with the document
    /// object given.
    public convenience init() {
        self.init(CBLMutableDocument())
    }

    
    /// Initializes a new Document object with the given ID. If a nil ID value is given,
    /// the document will be created with a new random UUID. The created document will be saved
    /// into a database when you call the Database's save() method with the document object given.
    ///
    /// - Parameter id: The document ID.
    public convenience init(_ id: String?) {
        self.init(CBLMutableDocument(id: id))
    }
    
    
    /// Initializes a new Document object with a new random UUID and the dictionary as the content.
    /// Allowed dictionary value types are Array, Date, Dictionary, Number, NSNull, String,
    /// ArrayObject, Blob, DictionaryObject. The Arrays and Dictionaries must contain only
    /// the above types. The created document will be saved into a database when you call the
    /// Database's save() method with the document object given.
    ///
    /// - Parameter dictionary: The dictionary object.
    public convenience init(dictionary: Dictionary<String, Any>?) {
        self.init(CBLMutableDocument())
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
        self.init(CBLMutableDocument(id: id))
        setDictionary(dictionary)
    }
    
    // MARK: Edit
    
    /// Returns the same MutableDocument object.
    ///
    /// - Returns: The MutableDocument object.
    public override func toMutable() -> MutableDocument {
        return self;
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
    
    
    /// Set an int value for the given key.
    ///
    /// - Parameters:
    ///   - value: The integer value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setInt(_ value: Int, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set an int64 value for the given key.
    ///
    /// - Parameters:
    ///   - value: The int64 value.
    ///   - key: The key.
    /// - Returns: The Document object.
    @discardableResult public func setInt64(_ value: Int64, forKey key: String) -> Self {
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
    
    
    /// Get a property's value as an MutableArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The MutableArrayObject object or nil if the property doesn't exist.
    public override func array(forKey key: String) -> MutableArrayObject? {
        return value(forKey: key) as? MutableArrayObject
    }
    
    
    /// Get a property's value as a MutableDictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: The MutableDictionaryObject object or nil if the key doesn't exist.
    public override func dictionary(forKey key: String) -> MutableDictionaryObject? {
        return value(forKey: key) as? MutableDictionaryObject
    }
    
    
    // MARK: Operators
    
    
    /// Equal to operator for comparing two Documents object.
    public static func == (doc1: MutableDocument, doc: MutableDocument) -> Bool {
        return doc._impl === doc._impl
    }
    
    
    // MARK: Subscript
    
    
    /// Subscripting access to a MutableFragment object that represents the value of the dictionary by key.
    ///
    /// - Parameter key: The key.
    public override subscript(key: String) -> MutableFragment {
        return MutableFragment(docImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLMutableDocument) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var docImpl: CBLMutableDocument {
        return _impl as! CBLMutableDocument
    }
    
}

public typealias Blob = CBLBlob
