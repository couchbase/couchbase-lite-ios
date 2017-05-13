//
//  ReadOnlyArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// ReadOnlyArrayProtocol defines a set of methods for readonly accessing array data. */
protocol ReadOnlyArrayProtocol: ReadOnlyArrayFragment {
    /// Gets a number of the items in the array.
    var count: Int { get }
    
    /// Gets value at the given index. The value types are Blob, ReadOnlyArrayObject, 
    /// ReadOnlyDictionaryObject, Number, or String based on the underlying data type; or nil 
    /// if the value is nil.
    /// - Parameter index: the index.
    /// - Returns: the value or nil.
    func getValue(_ index: Int) -> Any?
    
    /// Gets value at the given index as a string.
    /// Returns nil if the value doesn't exist, or its value is not a string.
    /// - Parameter index: the index.
    /// - Returns: the String value or nil.
    func getString(_ index: Int) -> String?
    
    /// Gets value at the given index as an integer.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Int value.
    func getInt(_ index: Int) -> Int
    
    /// Gets value at the given index as a float.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Float value.
    func getFloat(_ index: Int) -> Float
    
    /// Gets value at the given index as a double.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the property doesn't exist or does not have a numeric value.
    /// - Parameter index: the index.
    /// - Returns: the Double value.
    func getDouble(_ index: Int) -> Double
    
    /// Gets value at the given index as a boolean.
    /// Returns true if the value exists, and is either `true` or a nonzero number.
    /// - Parameter index: the index.
    /// - Returns: the Bool value.
    func getBoolean(_ index: Int) -> Bool
    
    /// Get value at the given index as a blob.
    /// Returns nil if the value doesn't exist, or its value is not a blob.
    /// - Parameter index: the index.
    /// - Returns: the Blob object or nil.
    func getBlob(_ index: Int) -> Blob?
    
    /// Gets value at the given index as an Date.
    /// JSON does not directly support dates, so the actual property value must be a string, which 
    /// is then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    /// - Parameter index: the index.
    /// - Returns: the Date object or nil.
    func getDate(_ index: Int) -> Date?
    
    /// Gets value as a ReadOnlyArrayObject, which is a mapping object of an array value.
    /// Returns nil if the value doesn't exists, or its value is not an array.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyArrayObject object or nil.
    func getArray(_ index: Int) -> ReadOnlyArrayObject?
    
    /// Get value at the given index as a ReadOnlyDictionaryObject, which is a mapping object of
    /// a dictionary value.
    /// Returns nil if the value doesn't exists, or its value is not a dictionary.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyDictionaryObject object or nil.
    func getDictionary(_ index: Int) -> ReadOnlyDictionaryObject?
    
    /// Gets content of the current object as an Array object. The values contained in the
    /// returned Array object are all JSON based values.
    /// - Returns: the Array object representing the content of the current object in
    ///            the JSON format.
    func toArray() -> Array<Any>
}

/// ReadOnlyArrayObject provides readonly access to array data.
public class ReadOnlyArrayObject: ReadOnlyArrayProtocol {
    public var count: Int {
        return Int(_impl.count)
    }
    
    
    public func getValue(_ index: Int) -> Any? {
        return DataConverter.convertGETValue(_impl.object(at: UInt(index)))
    }
    
    
    public func getString(_ index: Int) -> String? {
        return _impl.string(at: UInt(index))
    }
    
    
    public func getInt(_ index: Int) -> Int {
        return _impl.integer(at: UInt(index))
    }
    
    
    public func getFloat(_ index: Int) -> Float {
        return _impl.float(at: UInt(index))
    }
    
    
    public func getDouble(_ index: Int) -> Double {
        return _impl.double(at: UInt(index))
    }
    
    
    public func getBoolean(_ index: Int) -> Bool {
        return _impl.boolean(at: UInt(index))
    }
    
    
    public func getBlob(_ index: Int) -> Blob? {
        return _impl.blob(at: UInt(index))
    }
    
    
    public func getDate(_ index: Int) -> Date? {
        return _impl.date(at: UInt(index))
    }
    
    
    public func getArray(_ index: Int) -> ReadOnlyArrayObject? {
        return getValue(index) as? ReadOnlyArrayObject
    }
    
    
    public func getDictionary(_ index: Int) -> ReadOnlyDictionaryObject? {
        return getValue(index) as? ReadOnlyDictionaryObject
    }
    
    
    public func toArray() -> Array<Any> {
        return _impl.toArray()
    }
    
    
    // MARK: ReadOnlyArrayFragment
    
    
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
