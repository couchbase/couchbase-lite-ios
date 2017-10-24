//
//  ReadOnlyDictionaryObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// ReadOnlyDictionaryProtocol defines a set of methods for readonly accessing dictionary data.
protocol ReadOnlyDictionaryProtocol: ReadOnlyDictionaryFragment, Sequence {
    var count: Int { get }
    
    var keys: Array<String> { get }
    
    func value(forKey key: String) -> Any?
    
    func string(forKey key: String) -> String?
    
    func int(forKey key: String) -> Int
    
    func int64(forKey key: String) -> Int64
    
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


/// ReadOnlyDictionaryObject provides readonly access to dictionary data.
public class ReadOnlyDictionaryObject: ReadOnlyDictionaryProtocol {
    
    /// The number of entries in the dictionary.
    public var count: Int {
        return Int(_impl.count)
    }
    
    
    /// An array containing all keys, or an empty array if the dictionary has no entries.
    public var keys: Array<String> {
        return _impl.keys
    }
    
    
    /// Get a property's value as a ReadOnlyArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The ReadOnlyArrayObject object or nil.
    public func array(forKey key: String) -> ReadOnlyArrayObject? {
        return value(forKey: key) as? ReadOnlyArrayObject
    }
    
    
    /// Get a property's value as a Blob object.
    /// Returns nil if the property doesn't exist, or its value is not a blob.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Blob object or nil.
    public func blob(forKey key: String) -> Blob? {
        return _impl.blob(forKey: key)
    }
    
    
    /// Gets a property's value as a boolean value.
    /// Returns true if the value exists, and is either `true` or a nonzero number.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Bool value.
    public func boolean(forKey key: String) -> Bool {
        return _impl.boolean(forKey: key)
    }
    
    
    /// Gets a property's value as a Date value.
    /// JSON does not directly support dates, so the actual property value must be a string, which is
    /// then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Date value or nil
    public func date(forKey key: String) -> Date? {
        return _impl.date(forKey: key)
    }
    
    
    /// Get a property's value as a ReadOnlyDictionaryObject, which is a mapping object of
    /// a dictionary value.
    /// Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: THe ReadOnlyDictionaryObject object or nil.
    public func dictionary(forKey key: String) -> ReadOnlyDictionaryObject? {
        return value(forKey: key) as? ReadOnlyDictionaryObject
    }
    
    
    /// Gets a property's value as a float value.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Float value.
    public func float(forKey key: String) -> Float {
        return _impl.float(forKey: key)
    }
    
    
    /// Gets a property's value as a double value.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Double value.
    public func double(forKey key: String) -> Double {
        return _impl.double(forKey: key)
    }
    
    
    /// Gets a property's value as an int value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Int value.
    public func int(forKey key: String) -> Int {
        return _impl.integer(forKey: key)
    }
    
    
    /// Gets a property's value as an int64 value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Int64 value.
    public func int64(forKey key: String) -> Int64 {
        return _impl.longLong(forKey: key)
    }

    
    ///  Gets a property's value as a string.
    ///  Returns nil if the property doesn't exist, or its value is not a string.
    ///
    /// - Parameter key: The key.
    /// - Returns: The String object or nil.
    public func string(forKey key: String) -> String? {
        return _impl.string(forKey: key)
    }
    
    /// Gets a property's value. The value types are Blob, ReadOnlyArrayObject,
    /// ReadOnlyDictionaryObject, Number, or String based on the underlying data type; or nil
    /// if the value is nil or the property doesn't exist.
    ///
    /// - Parameter key: The key.
    /// - Returns: The value or nil.
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(_impl.object(forKey: key))
    }
    
    /// Tests whether a property exists or not.
    /// This can be less expensive than -objectForKey:, because it does not have to allocate an
    /// NSObject for the property value.
    ///
    /// - Parameter key: The key.
    /// - Returns: True of the property exists, otherwise false.
    public func contains(_ key: String) -> Bool {
        return _impl.containsObject(forKey: key)
    }
    
    
    /// Gets content of the current object as a Dictionary. The values contained in the
    /// returned Dictionary object are all JSON based values.
    ///
    /// - Returns: The Dictionary object representing the content of the current object in the
    ///            JSON format.
    public func toDictionary() -> Dictionary<String, Any> {
        return _impl.toDictionary()
    }
    
    
    // MARK: Sequence
    
    
    /// Gets  an iterator over the keys of the dictionary entries
    ///
    /// - Returns: The key iterator.
    public func makeIterator() -> IndexingIterator<[String]> {
        return _impl.keys.makeIterator();
    }
    
    
    // MARK: Subscript
    
    
    /// Subscript access to a ReadOnlyFragment object by key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLDictionary) {
        _impl = impl
        _impl.swiftObject = self
    }
    
    
    deinit {
        _impl.swiftObject = nil
    }
    
    
    let _impl: CBLDictionary
    
}
