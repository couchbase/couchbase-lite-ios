//
//  DictionaryObject.swift
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


/// DictionaryProtocol defines a set of methods for readonly accessing dictionary data.
public protocol DictionaryProtocol: DictionaryFragment {
    
    var count: Int { get }
    
    var keys: Array<String> { get }
    
    func value(forKey key: String) -> Any?
    
    func string(forKey key: String) -> String?
    
    func number(forKey key: String) -> NSNumber?
    
    func int(forKey key: String) -> Int
    
    func int64(forKey key: String) -> Int64
    
    func float(forKey key: String) -> Float
    
    func double(forKey key: String) -> Double
    
    func boolean(forKey key: String) -> Bool
    
    func date(forKey key: String) -> Date?
    
    func blob(forKey key: String) -> Blob?
    
    func array(forKey key: String) -> ArrayObject?
    
    func dictionary(forKey key: String) -> DictionaryObject?
    
    func contains(key: String) -> Bool
    
    func toDictionary() -> Dictionary<String, Any>
    
}


/// DictionaryObject provides readonly access to dictionary data.
public class DictionaryObject: DictionaryProtocol, Equatable, Hashable, Sequence {
    
    /// The number of entries in the dictionary.
    public var count: Int {
        return Int(_impl.count)
    }
    
    /// An array containing all keys, or an empty array if the dictionary has no entries.
    public var keys: Array<String> {
        return _impl.keys
    }
    
    /// Gets a property's value. The value types are Blob, ArrayObject,
    /// DictionaryObject, Number, or String based on the underlying data type; or nil
    /// if the value is nil or the property doesn't exist.
    ///
    /// - Parameter key: The key.
    /// - Returns: The value or nil.
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(_impl.value(forKey: key))
    }
    
    ///  Gets a property's value as a string.
    ///  Returns nil if the property doesn't exist, or its value is not a string.
    ///
    /// - Parameter key: The key.
    /// - Returns: The String object or nil.
    public func string(forKey key: String) -> String? {
        return _impl.string(forKey: key)
    }
    
    ///  Gets a property's value as a Number.
    ///  Returns nil if the property doesn't exist, or its value is not a number.
    ///
    /// - Parameter key: The key.
    /// - Returns: The String object or nil.
    public func number(forKey key: String) -> NSNumber? {
        return _impl.number(forKey: key)
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
    
    /// Get a property's value as a Blob object.
    /// Returns nil if the property doesn't exist, or its value is not a blob.
    ///
    /// - Parameter key: The key.
    /// - Returns: The Blob object or nil.
    public func blob(forKey key: String) -> Blob? {
        return value(forKey: key) as? Blob
    }
    
    /// Get a property's value as a ArrayObject, which is a mapping object of an array value.
    /// Returns nil if the property doesn't exists, or its value is not an array.
    ///
    /// - Parameter key: The key.
    /// - Returns: The ArrayObject object or nil.
    public func array(forKey key: String) -> ArrayObject? {
        return value(forKey: key) as? ArrayObject
    }
    
    /// Get a property's value as a DictionaryObject, which is a mapping object of
    /// a dictionary value.
    /// Returns nil if the property doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter key: The key.
    /// - Returns: THe DictionaryObject object or nil.
    public func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    /// Tests whether a property exists or not.
    /// This can be less expensive than -objectForKey:, because it does not have to allocate an
    /// NSObject for the property value.
    ///
    /// - Parameter key: The key.
    /// - Returns: True of the property exists, otherwise false.
    public func contains(key: String) -> Bool {
        return _impl.containsValue(forKey: key)
    }
    
    // MARK: Data
    
    /// Gets content of the current object as a Dictionary. The value types of
    /// the values contained in the returned Dictionary object are Array, Blob,
    /// Dictionary, Number types, NSNull, and String.
    ///
    /// - Returns: The Dictionary representing the content of the current object.
    public func toDictionary() -> Dictionary<String, Any> {
        var dict: [String: Any] = [:]
        for key in keys {
            let value = self.value(forKey: key)
            switch value {
            case let v as DictionaryObject:
                dict[key] = v.toDictionary()
            case let v as ArrayObject:
                dict[key] = v.toArray()
            default:
                dict[key] = value
            }
        }
        return dict
    }
    
    // MARK: Edit
    
    /// Returns a mutable copy of the dictionary object.
    ///
    /// - Returns: The MutableDocument object.
    public func toMutable() -> MutableDictionaryObject {
        switch _impl {
        case let impl as CBLDictionary:
            return MutableDictionaryObject(impl.toMutable())
        case let impl as CBLNewDictionary:
            return MutableDictionaryObject(impl.toMutable())
        default:
            fatalError("Invalid dictionary!!!")
        }
    }
    
    // MARK: Sequence
    
    /// Gets  an iterator over the keys of the dictionary entries
    ///
    /// - Returns: The key iterator.
    public func makeIterator() -> IndexingIterator<[String]> {
        return _impl.keys.makeIterator();
    }
    
    // MARK: Subscript
    
    /// Subscript access to a Fragment object by key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> Fragment {
        return Fragment(_impl[key])
    }
    
    // MARK: Equality
    
    /// Equal to operator for comparing two Dictionary objects.
    public static func == (dict1: DictionaryObject, dict2: DictionaryObject) -> Bool {
        return (dict1._impl as! NSObject) == (dict2._impl as! NSObject)
    }
    
    // MARK: Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_impl.hash)
    }
    
    // MARK: Internal
    
    init(_ impl: CBLDictionaryProtocol) {
        _impl = impl
        
        switch _impl {
        case let dict as CBLDictionary:
            dict.swiftObject = self
        case let dict as CBLNewDictionary:
            dict.swiftObject = self
        default:
            fatalError("Invalid dictionary!!!")
        }
    }
    
    deinit {
        switch _impl {
        case let dict as CBLDictionary:
            dict.swiftObject = nil
        case let dict as CBLNewDictionary:
            dict.swiftObject = nil
        default:
            fatalError("Invalid dictionary!!!")
        }
    }
    
    let _impl: CBLDictionaryProtocol
    
}
