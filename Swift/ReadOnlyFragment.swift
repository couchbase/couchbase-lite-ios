//
//  ReadOnlyFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// ReadOnlyFragmentProtocol provides readonly access to the data value wrapped by 
/// a fragment object.
protocol ReadOnlyFragmentProtocol {
    /// Gets the fragment value.
    /// The value types are Blob, ReadOnlyArray, ReadOnlyDictionary, Number, or String
    /// based on the underlying data type; or nil if the value is nil.
    var value: Any? { get }
    
    /// Gets the value as a string.
    /// Returns nil if the value is nil, or the value is not a string.
    var string: String? { get }
    
    /// Gets the value as an integer.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value is nil or is not a numeric value.
    var int: Int { get }
    
    /// Gets the value as a float.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value is nil or is not a numeric value.
    var float: Float { get }
    
    /// Gets the value as a double.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value is nil or is not a numeric value.
    var double: Double { get }
    
    /// Gets the value as a boolean.
    /// Returns true if the value is not nil nor NSNull, and is either `true` or a nonzero number.
    var boolean: Bool { get }
    
    /// Get the value as a Blob.
    /// Returns nil if the value is nil, or the value is not a Blob.
    var blob: Blob? { get }
    
    /// Gets the value as an Date.
    /// JSON does not directly support dates, so the actual property value must be a string, which is
    /// then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value is nil, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    var date: Date? { get }
    
    /// Get the value as a ReadOnlyArrayObject, a mapping object of an array value.
    /// Returns nil if the value is nil, or the value is not an array.
    var array: ReadOnlyArrayObject? { get }
    
    /// Get a property's value as a ReadOnlyDictionaryObject, a mapping object of a dictionary value.
    /// Returns nil if the value is nil, or the value is not a dictionary.
    var dictionary: ReadOnlyDictionaryObject? { get }
    
    /// Checks whether the value held by the fragment object exists or is nil value or not.
    var exists: Bool { get }
}

/// ReadOnlyArrayFragment protocol provides subscript access to ReadOnlyFragment objects by index.
protocol ReadOnlyArrayFragment {
    /// Subscript access to a ReadOnlyFragment object by index.
    /// - Parameter index: the index.
    /// - Returns: the ReadOnlyFragment object.
    subscript(index: Int) -> ReadOnlyFragment { get }
}

/// ReadOnlyDictionaryFragment protocol provides subscript access to ReadOnlyFragment objects by key.
protocol ReadOnlyDictionaryFragment {
    /// Subscript access to a ReadOnlyFragment object by key.
    /// - Parameter key: the key.
    /// - Returns: the ReadOnlyFragment object.
    subscript(key: String) -> ReadOnlyFragment { get }
}


public class ReadOnlyFragment: ReadOnlyFragmentProtocol,
                               ReadOnlyArrayFragment, ReadOnlyDictionaryFragment
{
    public var value: Any? {
        return DataConverter.convertGETValue(_impl.object)
    }
    
    
    public var string: String? {
        return _impl.string
    }
    
    
    public var int: Int {
        return _impl.integerValue
    }
    
    
    public var float: Float {
        return _impl.floatValue
    }
    
    
    public var double: Double {
        return _impl.doubleValue
    }
    
    
    public var boolean: Bool {
        return _impl.booleanValue
    }
    
    
    public var blob: Blob? {
        return _impl.blob
    }
    
    
    public var date: Date? {
        return _impl.date
    }
    
    
    public var array: ReadOnlyArrayObject? {
        return DataConverter.convertGETValue(_impl.array) as? ReadOnlyArrayObject
    }
    
    
    public var dictionary: ReadOnlyDictionaryObject? {
        return DataConverter.convertGETValue(_impl.dictionary) as? ReadOnlyDictionaryObject
    }
    
    
    public var exists: Bool {
        return _impl.exists
    }
    
    
    // MARK: ReadOnlyArrayFragment
    
    
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[UInt(index)])
    }
    
    
    // MARK: ReadOnlyDictionaryFragment
    
    
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    

    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLReadOnlyFragment
}
