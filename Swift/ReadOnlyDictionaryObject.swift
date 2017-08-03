//
//  ReadOnlyDictionaryObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** ReadOnlyDictionaryProtocol defines a set of methods for readonly accessing dictionary data. */
protocol ReadOnlyDictionaryProtocol: ReadOnlyDictionaryFragment, Sequence {
    var count: Int { get }
    
    var keys: Array<String> { get }
    
    func value(forKey key: String) -> Any?
    
    func string(forKey key: String) -> String?
    
    func int(forKey key: String) -> Int
    
    func float(forKey key: String) -> Float
    
    func double(forKey key: String) -> Double
    
    func boolean(forKey key: String) -> Bool
    
    func blob(forKey key: String) -> Blob?
    
    func date(forKey key: String) -> Date?
    
    func array(forKey key: String) -> ReadOnlyArrayObject?
    
    func dictionary(forKey key: String) -> ReadOnlyDictionaryObject?
    
    func contains(_ key: String) -> Bool
    
    func toDictionary() -> Dictionary<String, Any>
}

/** ReadOnlyDictionaryObject provides readonly access to dictionary data. */
public class ReadOnlyDictionaryObject: ReadOnlyDictionaryProtocol {
    /// The number of entries in the dictionary.
    public var count: Int {
        return Int(_impl.count)
    }
    
    
    /** An array containing all keys, or an empty array if the dictionary has no entries. */
    public var keys: Array<String> {
        return _impl.keys
    }
    
    
    /** Gets a property's value. The value types are Blob, ReadOnlyArrayObject,
        ReadOnlyDictionaryObject, Number, or String based on the underlying data type; or nil
        if the value is nil or the property doesn't exist.
        - Parameter key: the key.
        - Returns: the object value or nil. */
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(_impl.object(forKey: key))
    }
    
    
    /** Gets a property's value as a string.
        Returns nil if the property doesn't exist, or its value is not a string.
        - Parameter key: the key.
        - Returns: the String object or nil. */
    public func string(forKey key: String) -> String? {
        return _impl.string(forKey: key)
    }
    
    
    /** Gets a property's value as an integer.
        Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
        Returns 0 if the property doesn't exist or does not have a numeric value.
        - Parameter key: the key.
        - Returns: the Int value. */
    public func int(forKey key: String) -> Int {
        return _impl.integer(forKey: key)
    }
    
    
    /** Gets a property's value as a float.
        Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
        Returns 0.0 if the property doesn't exist or does not have a numeric value.
        - Parameter key: the key.
        - Returns: the Float value. */
    public func float(forKey key: String) -> Float {
        return _impl.float(forKey: key)
    }
    
    
    /** Gets a property's value as a double.
        Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
        Returns 0.0 if the property doesn't exist or does not have a numeric value.
        - Parameter key: the key.
        - Returns: the Double value. */
    public func double(forKey key: String) -> Double {
        return _impl.double(forKey: key)
    }
    
    
    /** Gets a property's value as a boolean.
        Returns true if the value exists, and is either `true` or a nonzero number.
        - Parameter key: the key.
        - Returns: the Bool value. */
    public func boolean(forKey key: String) -> Bool {
        return _impl.boolean(forKey: key)
    }
    
    
    /** Get a property's value as a blob.
        Returns nil if the property doesn't exist, or its value is not a blob.
        - Parameter key: the key.
        - Returns: the Blob object or nil. */
    public func blob(forKey key: String) -> Blob? {
        return _impl.blob(forKey: key)
    }
    
    
    /** Gets a property's value as an Date.
        JSON does not directly support dates, so the actual property value must be a string, which is
        then parsed according to the ISO-8601 date format (the default used in JSON.)
        Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
        NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
        without milliseconds.
        - Parameter key: the key.
        - Returns: the Date object or nil. */
    public func date(forKey key: String) -> Date? {
        return _impl.date(forKey: key)
    }
    
    
    /** Get a property's value as a ReadOnlyArrayObject, which is a mapping object of an array value.
        Returns nil if the property doesn't exists, or its value is not an array.
        - Parameter key: the key.
        - Returns: the ReadOnlyArrayObject object or nil. */
    public func array(forKey key: String) -> ReadOnlyArrayObject? {
        return value(forKey: key) as? ReadOnlyArrayObject
    }
    
    
    /** Get a property's value as a ReadOnlyDictionaryObject, which is a mapping object of
        a dictionary value.
        Returns nil if the property doesn't exists, or its value is not a dictionary.
        - Parameter key: the key.
        - Returns: the ReadOnlyDictionaryObject object or nil. */
    public func dictionary(forKey key: String) -> ReadOnlyDictionaryObject? {
        return value(forKey: key) as? ReadOnlyDictionaryObject
    }
    
    
    /** Tests whether a property exists or not.
        This can be less expensive than -objectForKey:, because it does not have to allocate an
        NSObject for the property value.
        - Parameter key: the key.
        - Returns: the boolean value representing whether a property exists or not. */
    public func contains(_ key: String) -> Bool {
        return _impl.containsObject(forKey: key)
    }
    
    
    /** Gets content of the current object as a Dictionary. The values contained in the
        returned Dictionary object are all JSON based values.
        - Returns: the Dictionary object representing the content of the current object in the
                   JSON format. */
    public func toDictionary() -> Dictionary<String, Any> {
        return _impl.toDictionary()
    }
    
    
    // MARK: Sequence
    
    
    /** Gets  an iterator over the keys of the dictionary entries
        - Returns: a key iterator. */
    public func makeIterator() -> IndexingIterator<[String]> {
        return _impl.keys.makeIterator();
    }
    
    
    // MARK: Subscript
    
    
    /** Subscript access to a ReadOnlyFragment object by key.
        - Parameter key: the key.
        - Returns: the ReadOnlyFragment object. */
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyDictionary) {
        _impl = impl
        _impl.swiftObject = self
    }
    
    
    deinit {
        _impl.swiftObject = nil
    }
    
    
    let _impl: CBLReadOnlyDictionary
}
