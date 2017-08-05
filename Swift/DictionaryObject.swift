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

    // MARK: Type Setters
    
    @discardableResult func setArray(_ value: ArrayObject?, forKey key: String) -> Self
    
    @discardableResult func setBlob(_ value: Blob?, forKey key: String) -> Self
    
    @discardableResult func setBoolean(_ value: Bool, forKey key: String) -> Self
    
    @discardableResult func setDate(_ value: Date?, forKey key: String) -> Self
    
    @discardableResult func setDictionary(_ value: DictionaryObject?, forKey key: String) -> Self
    
    @discardableResult func setDouble(_ value: Double, forKey key: String) -> Self
    
    @discardableResult func setFloat(_ value: Float, forKey key: String) -> Self
    
    @discardableResult func setInteger(_ value: Int, forKey key: String) -> Self
    
    @discardableResult func setString(_ value: String?, forKey key: String) -> Self
    
    @discardableResult func setValue(_ value: Any?, forKey key: String) -> Self
    
    // MARK: Setting content with a Dictionary
    
    @discardableResult func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self
    
    // MARK: Removing Entries
    
    @discardableResult func remove(forKey key: String) -> Self
    
    // MARK: Getting DictionaryObject and ArrayObject
    
    func array(forKey key: String) -> ArrayObject? /* override */
    
    func dictionary(forKey key: String) -> DictionaryObject? /* override */
    
}


/// DictionaryObject provides access to dictionary data.
public class DictionaryObject: ReadOnlyDictionaryObject, DictionaryProtocol {
    
    // MARK: Initializers
    
    
    /// Initialize a new empty CBLDictionary object.
    public init() {
        super.init(CBLDictionary())
    }
    
    
    /// Initialzes a new DictionaryObject object with dictionary content. Allowed value types are
    /// Array, Date, Dictionary, Number, NSNull, String, ArrayObject, Blob, DictionaryObject.
    /// The Arrays and Dictionaries must contain only the above types.
    ///
    /// - Parameter dictionary: the dictionary object.
    public init(dictionary: Dictionary<String, Any>?) {
        super.init(CBLDictionary())
        setDictionary(dictionary)
    }
    
    
    // MARK: Type Setters
    
    
    /// Set an ArrayObject object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The ArrayObject object.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setArray(_ value: ArrayObject?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a Blob object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Blob object.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setBlob(_ value: Blob?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a boolean value for the given key.
    ///
    /// - Parameters:
    ///   - value: The boolean value.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setBoolean(_ value: Bool, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a Date object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Date object.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setDate(_ value: Date?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a DictionaryObject object for the given key. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The DictionaryObject object.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setDictionary(_ value: DictionaryObject?, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a double value for the given key.
    ///
    /// - Parameters:
    ///   - value:  The double value.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setDouble(_ value: Double, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a float value for the given key.
    ///
    /// - Parameters:
    ///   - value: The float value.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setFloat(_ value: Float, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set an integer value for the given key.
    ///
    /// - Parameters:
    ///   - value: The integer value.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setInteger(_ value: Int, forKey key: String) -> Self {
        return setValue(value, forKey: key)
    }
    
    
    /// Set a String value for the given key.
    ///
    /// - Parameters:
    ///   - value: The String value.
    ///   - key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult func setString(_ value: String?, forKey key: String) -> Self {
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
    /// - Returns: The DictionaryObject object.
    @discardableResult public func setValue(_ value: Any?, forKey key: String) -> Self {
        dictImpl.setObject(DataConverter.convertSETValue(value), forKey: key)
        return self
    }
    
    
    // MARK: Setting content with a Dictionary
    
    
    /// Set a dictionary as a content. Allowed value types are Array, Date, Dictionary,
    /// Number types, NSNull, String, ArrayObject, Blob, DictionaryObject. The Arrays and
    /// Dictionaries must contain only the above types. Setting the new dictionary content
    /// will replace the current data including the existing ArrayObject and DictionaryObject
    /// objects.
    ///
    /// - Parameter dictionary: The dictionary.
    /// - Returns: The DictionaryObject object.
    @discardableResult public func setDictionary(_ dictionary: Dictionary<String, Any>?) -> Self {
        dictImpl.setDictionary(DataConverter.convertSETDictionary(dictionary))
        return self
    }
    
    
    // MARK: Removing Entries
    
    
    /// Removes a given key and its value from the dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: The DictionaryObject object.
    @discardableResult public func remove(forKey key: String) -> Self {
        dictImpl.removeObject(forKey: key)
        return self
    }
    
    
    // MARK: Getting DictionaryObject and ArrayObject
    
    
    /// Get a property's value as an ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The ArrayObject object or nil if the property doesn't exist.
    public override func array(forKey key: String) -> ArrayObject? {
        return self.value(forKey: key) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of a dictionary
    /// value. Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: The DictionaryObject object.
    public override func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    
    // MARK: Subscript
    
    
    /// Subscripting access to a Fragment object that represents the value of the dictionary
    /// by key.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Fragment object.
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
