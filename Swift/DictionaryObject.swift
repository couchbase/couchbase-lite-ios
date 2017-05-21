//
//  DictionaryObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// DictionaryProtocol defines a set of methods for getting and setting dictionary data.
protocol DictionaryProtocol: ReadOnlyDictionaryProtocol, DictionaryFragment {
    /// Set a dictionary as a content. Allowed value types are Array, Date, Dictionary,
    /// Number, NSNull, String, ArrayObject, Blob, DictionaryObject. The Arrays and
    /// Dictionaries must contain only the above types. Setting the new dictionary content 
    /// will replace the current data including the existing ArrayObject and DictionaryObject 
    /// objects.
    /// - Parameter dictionary: the dictionary.
    /// - Returns: the DictionaryProtocol object.
    @discardableResult func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self
    
    /// Set an object value by key. Setting the value to nil will remove the property. 
    /// Allowed value types are Array, Date, Dictionary, Number, NSNull, String, ArrayObject, 
    /// Blob, DictionaryObject. The Arrays and Dictionaries must contain only the above types. 
    /// An Date object will be converted to an ISO-8601 format string.
    /// - Parameter value: the object value.
    /// - Returns: the DictionaryProtocol object.
    @discardableResult func set(_ value: Any?, forKey key: String) -> Self
    
    /// Removes a given key and its value from the dictionary.
    /// - Parameter key:  the key.
    /// - Returns: the DictionaryProtocol object.
    @discardableResult func remove(forKey key: String) -> Self
    
    /// Get a property's value as an ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    /// - Parameter key: the key.
    /// - Returns: the ArrayObject object or nil if the property doesn't exist.
    /* override */ func array(forKey key: String) -> ArrayObject?
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    /// - Parameter key: the key.
    /// - Returns: the DictionaryObject object or nil if the key doesn't exist.
    /* override */ func dictionary(forKey key: String) -> DictionaryObject?
}

/// DictionaryObject provides access to dictionary data.
public class DictionaryObject: ReadOnlyDictionaryObject, DictionaryProtocol {
    /// Initialize a new empty CBLDictionary object.
    public init() {
        super.init(CBLDictionary())
    }
    
    
    /// Initialzes a new DictionaryObject object with dictionary content. Allowed value types are 
    /// Array, Date, Dictionary, Number, NSNull, String, ArrayObject, Blob, DictionaryObject.
    /// The Arrays and Dictionaries must contain only the above types.
    /// - Parameter dictionary: the dictionary object.
    public init(dictionary: Dictionary<String, Any>?) {
        super.init(CBLDictionary())
        setDictionary(dictionary)
    }
    
    
    /// Set a dictionary as a content. Allowed value types are Array, Date, Dictionary,
    /// Number, NSNull, String, ArrayObject, Blob, DictionaryObject. The Arrays and
    /// Dictionaries must contain only the above types. Setting the new dictionary content
    /// will replace the current data including the existing ArrayObject and DictionaryObject
    /// objects.
    /// - Parameter dictionary: the dictionary.
    /// - Returns: the DictionaryObject object.
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        dictImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    /// Set an object value by key. Setting the value to nil will remove the property.
    /// Allowed value types are Array, Date, Dictionary, Number, NSNull, String, ArrayObject,
    /// Blob, DictionaryObject. The Arrays and Dictionaries must contain only the above types.
    /// An Date object will be converted to an ISO-8601 format string.
    /// - Parameter value: the object value.
    /// - Returns: the DictionaryObject object.
    @discardableResult public func set(_ value: Any?, forKey key: String) -> Self {
        dictImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    /// Removes a given key and its value from the dictionary.
    /// - Parameter key:  the key.
    /// - Returns: the DictionaryObject object.
    @discardableResult public func remove(forKey key: String) -> Self {
        dictImpl.removeObject(forKey: key)
        return self
    }
    
    
    /// Get a property's value as an ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    /// - Parameter key: the key.
    /// - Returns: the ArrayObject object or nil if the property doesn't exist.
    public override func array(forKey key: String) -> ArrayObject? {
        return self.value(forKey: key) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    /// - Parameter key: the key.
    /// - Returns: the DictionaryObject object or nil if the key doesn't exist.
    public override func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    
    // MARK: DictionaryFragment
    
    
    /// Subscripting access to a Fragment object that represents the value of the dictionary 
    /// by key.
    /// - Parameter key: the key.
    /// - Returns: the Fragment object.
    public override subscript(key: String) -> Fragment {
        return Fragment(dictImpl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLDictionary) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var dictImpl: CBLDictionary {
        return _impl as! CBLDictionary
    }
}
