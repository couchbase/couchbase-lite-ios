//
//  Result.swift
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


/// Result represents a single row in the query result. The projecting result value can be
/// accessed either by using a zero based index or by a key corresponding to the
/// SelectResult objects given when constructing the Query object.
///
/// A key used for accessing the projecting result value could be one of the followings:
/// * The alias name of the SelectResult object.
/// * The last component of the keypath or property name of the property expression used
///   when creating the SelectResult object.
/// * The provision key in $1, $2, ...$N format for the SelectResult that doesn't have
///   an alias name specified or is not a property expression such as an aggregate function
///   expression (e.g. count(), avg(), min(), max(), sum() and etc). The number suffix
///   after the '$' character is a running number starting from one.
public final class Result : ArrayProtocol, DictionaryProtocol, Sequence {
    
    // MARK: ReadOnlyArrayProtocol
    
    
    /// A number of the projecting values in the result.
    public var count: Int {
        return Int(impl.count)
    }
    
    
    /// The projecting result value at the given index.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The value.
    public func value(at index: Int) -> Any? {
        return DataConverter.convertGETValue(impl.value(at: UInt(index)))
    }
    
    
    /// The projecting result value at the given index as a String value.
    /// Returns nil if the value is not a string.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The String object or nil.
    public func string(at index: Int) -> String? {
        return impl.string(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as a Number value.
    /// Returns nil if the value is not a number.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Number value.
    public func number(at index: Int) -> NSNumber? {
        return impl.number(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as an Int value.
    /// Returns 0 if the value is not a numeric value.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Int value.
    public func int(at index: Int) -> Int {
        return impl.integer(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as an Int64 value.
    /// Returns 0 if the value is not a numeric value.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Int value.
    public func int64(at index: Int) -> Int64 {
        return impl.longLong(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as a Double value.
    /// Returns 0.0 if the value is not a numeric value.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Double value.
    public func double(at index: Int) -> Double {
        return impl.double(at: UInt(index))
    }
    
    /// The projecting result value at the given index as a Float value.
    /// Returns 0.0 if the value is not a numeric value.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Float value.
    public func float(at index: Int) -> Float {
        return impl.float(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as a Boolean value.
    /// Returns true if the value is not null, and is either `true` or a nonzero number.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Bool value.
    public func boolean(at index: Int) -> Bool {
        return impl.boolean(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as a Blob value.
    /// Returns nil if the value is not a blob.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Blob value or nil.
    public func blob(at index: Int) -> Blob? {
        return value(at: index) as? Blob
    }
    
    
    /// The projecting result value at the given index as a Date value.
    /// Returns nil if the value is not a string and is not parseable as a date.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The Date value or nil.
    public func date(at index: Int) -> Date? {
        return impl.date(at: UInt(index))
    }
    
    
    /// The projecting result value at the given index as a readonly ArrayObject value.
    /// Returns nil if the value is not an array.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The ReadOnlyArrayObject or nil.
    public func array(at index: Int) -> ArrayObject? {
        return value(at: index) as? ArrayObject
    }
    
    
    /// The projecting result value at the given index as a readonly DictionaryObject value.
    /// Returns nil if the value is not a dictionary.
    ///
    /// - Parameter index: The select result index.
    /// - Returns: The ReadOnlyDictionaryObject or nil.
    public func dictionary(at index: Int) -> DictionaryObject? {
        return value(at: index) as? DictionaryObject
    }
    
    
    /// Gets all values as an Array. The value types of the values contained
    /// in the returned Array object are Array, Blob, Dictionary, Number types,
    /// NSNull, and String.
    ///
    /// - Returns: The Array representing all values.
    public func toArray() -> Array<Any> {
        return impl.toArray()
    }
    
    // MARK: ReadOnlyArrayFragment
    
    
    /// Subscript access to a ReadOnlyFragment object of the projecting result
    /// value at the given index.
    ///
    /// - Parameter index: The select result index.
    public subscript(index: Int) -> Fragment {
        return Fragment(impl[UInt(index)])
    }
    
    
    // MARK: ReadOnlyDictionaryProtocol
    
    
    /// All projecting keys.
    public var keys: Array<String> {
        return impl.keys
    }
    
    
    /// The projecting result value for the given key.
    /// Returns nil if the key doesn't exist.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The value or nil.
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(impl.value(forKey: key))
    }
    
    
    /// The projecting result value for the given key as a String value.
    /// Returns nil if the key doesn't exist, or the value is not a string.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The String value or nil.
    public func string(forKey key: String) -> String? {
        return impl.string(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a Number value.
    /// Returns nil if the key doesn't exist, or the value is not a number.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Number value or nil.
    public func number(forKey key: String) -> NSNumber? {
        return impl.number(forKey: key)
    }
    
    
    /// The projecting result value for the given key as an Int value.
    /// Returns 0 if the key doesn't exist, or the value is not a numeric value.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Int value.
    public func int(forKey key: String) -> Int {
        return impl.integer(forKey: key)
    }
    
    
    /// The projecting result value for the given key as an Int64 value.
    /// Returns 0 if the key doesn't exist, or the value is not a numeric value.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Int value.
    public func int64(forKey key: String) -> Int64 {
        return impl.longLong(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a Float value.
    /// Returns 0.0 if the key doesn't exist, or the value is not a numeric value.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The float value.
    public func float(forKey key: String) -> Float {
        return impl.float(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a Double value.
    /// Returns 0.0 if the key doesn't exist, or the value is not a numeric value.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Double value.
    public func double(forKey key: String) -> Double {
        return impl.double(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a Boolean value.
    /// Returns true if the key doesn't exist, or
    /// the value is not null, and is either `true` or a nonzero number.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Bool value.
    public func boolean(forKey key: String) -> Bool {
        return impl.boolean(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a Blob value.
    /// Returns nil if the key doesn't exist, or the value is not a blob.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Blob value or nil.
    public func blob(forKey key: String) -> Blob? {
        return value(forKey: key) as? Blob
    }
    
    
    /// The projecting result value for the given key as a Date value.
    /// Returns nil if the key doesn't exist, or
    /// the value is not a string and is not parseable as a date.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The Date value or nil.
    public func date(forKey key: String) -> Date? {
        return impl.date(forKey: key)
    }
    
    
    /// The projecting result value for the given key as a readonly ArrayObject value.
    /// Returns nil if the key doesn't exist, or the value is not an array.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The ReadOnlyArrayObject value or nil.
    public func array(forKey key: String) -> ArrayObject? {
        return value(forKey: key) as? ArrayObject
    }
    
    
    /// The projecting result value for the given key as a readonly DictionaryObject value.
    /// Returns nil if the key doesn't exist, or the value is not a dictionary.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: The ReadOnlyDictionaryObject or nil.
    public func dictionary(forKey key: String) -> DictionaryObject? {
        return value(forKey: key) as? DictionaryObject
    }
    
    
    /// Tests whether a projecting result key exists or not.
    ///
    /// - Parameter key: The select result key.
    /// - Returns: True if exists, otherwise false.
    public func contains(key: String) -> Bool {
        return impl.containsValue(forKey: key)
    }
    
    
    /// Gets all values as a Dictionary. The value types of the values contained
    /// in the returned Dictionary object are Array, Blob, Dictionary,
    /// Number types, NSNull, and String.
    ///
    /// - Returns: The Dictionary representing all values.
    public func toDictionary() -> Dictionary<String, Any> {
        return impl.toDictionary()
    }
    
    
    // MARK: Sequence
    
    
    /// Gets  an iterator over the prjecting result keys.
    ///
    /// - Returns: The IndexingIterator object of all result keys.
    public func makeIterator() -> IndexingIterator<[String]> {
        return impl.keys.makeIterator();
    }
    
    
    // MARK: DictionaryFragment
    
    
    /// Subscript access to a ReadOnlyFragment object of the projecting result
    /// value for the given key.
    ///
    /// - Parameter key: The select result key.
    public subscript(key: String) -> Fragment {
        return Fragment(impl[key])
    }
    
    // MARK: Internal
    
    private var impl: CBLQueryResult
    
    init(impl: CBLQueryResult) {
        self.impl = impl
    }
}
