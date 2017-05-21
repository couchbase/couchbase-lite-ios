//
//  ReadOnlyArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// ReadOnlyArrayProtocol defines a set of methods for readonly accessing array data. */
protocol ReadOnlyArrayProtocol: ReadOnlyArrayFragment, Sequence {
    var count: Int { get }
    
    func value(at index: Int) -> Any?
    
    func string(at index: Int) -> String?
    
    func int(at index: Int) -> Int
    
    func float(at index: Int) -> Float
    
    func double(at index: Int) -> Double
    
    func boolean(at index: Int) -> Bool
    
    func blob(at index: Int) -> Blob?
    
    func date(at index: Int) -> Date?
    
    func array(at index: Int) -> ReadOnlyArrayObject?
    
    func dictionary(at index: Int) -> ReadOnlyDictionaryObject?
    
    func toArray() -> Array<Any>
}

/// ReadOnlyArrayObject provides readonly access to array data.
public class ReadOnlyArrayObject: ReadOnlyArrayProtocol {
    /// Gets a number of the items in the array.
    public var count: Int {
        return Int(_impl.count)
    }
    
    
    /// Gets value at the given index. The value types are Blob, ReadOnlyArrayObject,
    /// ReadOnlyDictionaryObject, Number, or String based on the underlying data type; or nil
    /// if the value is nil.
    /// - Parameter index: the index.
    /// - Returns: the value or nil.
    public func value(at index: Int) -> Any? {
        return DataConverter.convertGETValue(_impl.object(at: UInt(index)))
    }
    
    
    /// Gets value at the given index as a string.
    /// Returns nil if the value doesn't exist, or its value is not a string.
    /// - Parameter index: the index.
    /// - Returns: the String value or nil.
    public func string(at index: Int) -> String? {
        return _impl.string(at: UInt(index))
    }
    
    
    /// Gets value at the given index as an integer.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Int value.
    public func int(at index: Int) -> Int {
        return _impl.integer(at: UInt(index))
    }
    
    
    /// Gets value at the given index as a float.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Float value.
    public func float(at index: Int) -> Float {
        return _impl.float(at: UInt(index))
    }
    
    
    /// Gets value at the given index as a double.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Double value.
    public func double(at index: Int) -> Double {
        return _impl.double(at: UInt(index))
    }
    
    
    /// Gets value at the given index as a boolean.
    /// Returns true if the value exists, and is either `true` or a nonzero number.
    /// - Parameter index: the index.
    /// - Returns: the Bool value.
    public func boolean(at index: Int) -> Bool {
        return _impl.boolean(at: UInt(index))
    }
    
    
    /// Get value at the given index as a blob.
    /// Returns nil if the value doesn't exist, or its value is not a blob.
    /// - Parameter index: the index.
    /// - Returns: the Blob object or nil.
    public func blob(at index: Int) -> Blob? {
        return _impl.blob(at: UInt(index))
    }
    
    
    /// Gets value at the given index as an Date.
    /// JSON does not directly support dates, so the actual property value must be a string, which
    /// is then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    /// - Parameter index: the index.
    /// - Returns: the Date object or nil.
    public func date(at index: Int) -> Date? {
        return _impl.date(at: UInt(index))
    }
    
    
    /// Gets value as a ReadOnlyArrayObject, which is a mapping object of an array value.
    /// Returns nil if the value doesn't exists, or its value is not an array.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyArrayObject object or nil.
    public func array(at index: Int) -> ReadOnlyArrayObject? {
        return value(at: index) as? ReadOnlyArrayObject
    }
    
    
    /// Get value at the given index as a ReadOnlyDictionaryObject, which is a mapping object of
    /// a dictionary value.
    /// Returns nil if the value doesn't exists, or its value is not a dictionary.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyDictionaryObject object or nil.
    public func dictionary(at index: Int) -> ReadOnlyDictionaryObject? {
        return value(at: index) as? ReadOnlyDictionaryObject
    }
    
    
    /// Gets content of the current object as an Array object. The values contained in the
    /// returned Array object are all JSON based values.
    /// - Returns: the Array object representing the content of the current object in
    ///            the JSON format.
    public func toArray() -> Array<Any> {
        return _impl.toArray()
    }
    
    
    // MARK: Sequence
    
    
    /// Gets  an iterator over items in the array.
    /// - Returns: an array item iterator.
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
    
    
    // MARK: ReadOnlyArrayFragment
    
    
    /// Subscript access to a ReadOnlyFragment object by index.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyFragment object.
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[UInt(index)])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyArray) {
        _impl = impl
        _impl.swiftObject = self
    }
    
    
    deinit {
        _impl.swiftObject = nil
    }
    
    
    let _impl: CBLReadOnlyArray
}
