//
//  ArrayObject.swift
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


/// ArrayProtocol defines a set of methods for readonly accessing array data.
protocol ArrayProtocol: ArrayFragment {
    var count: Int { get }
    
    func value(at index: Int) -> Any?
    
    func string(at index: Int) -> String?
    
    func int(at index: Int) -> Int
    
    func int64(at index: Int) -> Int64
    
    func float(at index: Int) -> Float
    
    func double(at index: Int) -> Double
    
    func number(at index: Int) -> NSNumber?
    
    func boolean(at index: Int) -> Bool
    
    func blob(at index: Int) -> Blob?
    
    func date(at index: Int) -> Date?
    
    func array(at index: Int) -> ArrayObject?
    
    func dictionary(at index: Int) -> DictionaryObject?
    
    func toArray() -> Array<Any>
}


/// ArrayObject provides readonly access to array data.
public class ArrayObject: ArrayProtocol, Equatable, Hashable, Sequence {
    
    /// Gets a number of the items in the array.
    public var count: Int {
        return Int(_impl.count)
    }
    
    /// Gets the value at the given index. The value types are Blob, ArrayObject,
    /// DictionaryObject, Number, or String based on the underlying data type.
    ///
    /// - Parameter index: The index.
    /// - Returns: The value located at the index.
    public func value(at index: Int) -> Any? {
        return DataConverter.convertGETValue(_impl.value(at: UInt(index)))
    }
    
    /// Gets the value at the given index as a string.
    /// Returns nil if the value doesn't exist, or its value is not a string
    ///
    /// - Parameter index: The index.
    /// - Returns: The String object.
    public func string(at index: Int) -> String? {
        return _impl.string(at: UInt(index))
    }
    
    
    /// Gets value at the given index as a Number value.
    ///
    /// - Parameter index: The index.
    /// - Returns: The number value located at the index.
    public func number(at index: Int) -> NSNumber? {
        return _impl.number(at: UInt(index))
    }
    
    
    /// Gets value at the given index as an int value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value doesn't exist or does not have a numeric value.
    ///
    /// - Parameter index: The index.
    /// - Returns: The int value located at the index.
    public func int(at index: Int) -> Int {
        return _impl.integer(at: UInt(index))
    }
    
    /// Gets value at the given index as an int64 value.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value doesn't exist or does not have a numeric value.
    ///
    /// - Parameter index: The index.
    /// - Returns: The int64 value located at the index.
    public func int64(at index: Int) -> Int64 {
        return _impl.longLong(at: UInt(index))
    }
    
    
    /// Gets the value at the given index as a float value.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    //// Returns 0.0 if the value doesn't exist or does not have a numeric value.
    ///
    /// - Parameter index: The index.
    /// - Returns: The Float value located at the index.
    public func float(at index: Int) -> Float {
        return _impl.float(at: UInt(index))
    }
    
    
    /// Gets the value at the given index as a double value.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    ///
    /// - Parameter index: The index.
    /// - Returns: The Double value located at the index.
    public func double(at index: Int) -> Double {
        return _impl.double(at: UInt(index))
    }
    
    
    /// Gets the value at the given index as a boolean value.
    /// Returns true if the value exists, and is either `true` or a nonzero number.
    ///
    /// - Parameter index: The index.
    /// - Returns: The Bool value located at the index.
    public func boolean(at index: Int) -> Bool {
        return _impl.boolean(at: UInt(index))
    }
    
    
    /// Gets value at the given index as an Date.
    /// JSON does not directly support dates, so the actual property value must be a string, which
    /// is then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    ///
    /// - Parameter index: The index.
    /// - Returns: The Date value at the given index.
    public func date(at index: Int) -> Date? {
        return _impl.date(at: UInt(index))
    }
    
    
    /// Get the Blob value at the given index.
    /// Returns nil if the value doesn't exist, or its value is not a blob.
    ///
    /// - Parameter index: The index.
    /// - Returns: The Blob value located at the index.
    public func blob(at index: Int) -> Blob? {
        return value(at: index) as? Blob
    }
    
    
    /// Gets the value at the given index as a ArrayObject value, which is a mapping object
    /// of an array value.
    /// Returns nil if the value doesn't exists, or its value is not an array.
    ///
    /// - Parameter index: The index.
    /// - Returns: The ArrayObject at the given index.
    public func array(at index: Int) -> ArrayObject? {
        return value(at: index) as? ArrayObject
    }
    
    
    /// Get the value at the given index as a DictionaryObject value, which is a
    /// mapping object of a dictionary value.
    /// Returns nil if the value doesn't exists, or its value is not a dictionary.
    ///
    /// - Parameter index: The index.
    /// - Returns: The DictionaryObject
    public func dictionary(at index: Int) -> DictionaryObject? {
        return value(at: index) as? DictionaryObject
    }

    
    /// Gets content of the current object as an Array. The value types of the values
    /// contained in the returned Array object are Array, Blob, Dictionary,
    /// Number types, NSNull, and String.
    ///
    /// - Returns: The Array representing the content of the current object.
    public func toArray() -> Array<Any> {
        return _impl.toArray()
    }
    
    
    // MARK: Sequence
    
    
    /// Gets an iterator over items in the array.
    ///
    /// - Returns: The array item iterator.
    public func makeIterator() -> AnyIterator<Any> {
        var index = 0;
        let count = self.count
        return AnyIterator {
            if index < count {
                let v = self.value(at: index)
                index += 1
                return v;
            }
            return nil
        }
    }
    
    
    // MARK: Subscript
    
    
    /// Subscript access to a Fragment object by index
    ///
    /// - Parameter index: The Index.
    public subscript(index: Int) -> Fragment {
        return Fragment(_impl[UInt(index)])
    }
    
    
    // MARK: Equality
    
    
    /// Equal to operator for comparing two Array objects.
    public static func == (array1: ArrayObject, array2: ArrayObject) -> Bool {
        return array1._impl == array2._impl
    }
    
    
    // MARK: Hashable
    
    public var hashValue: Int {
        return _impl.hash;
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLArray) {
        _impl = impl
        _impl.swiftObject = self
    }
    
    
    deinit {
        _impl.swiftObject = nil
    }
    
    
    let _impl: CBLArray
    
}
