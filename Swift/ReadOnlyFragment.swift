//
//  ReadOnlyFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// ReadOnlyFragmentProtocol provides readonly access to the data value wrapped by a fragment object.
protocol ReadOnlyFragmentProtocol {
    var value: Any? { get }
    
    var string: String? { get }
    
    var int: Int { get }
    
    var float: Float { get }
    
    var double: Double { get }
    
    var boolean: Bool { get }
    
    var blob: Blob? { get }
    
    var date: Date? { get }
    
    var array: ReadOnlyArrayObject? { get }
    
    var dictionary: ReadOnlyDictionaryObject? { get }
    
    var exists: Bool { get }
}


/// ReadOnlyArrayFragment protocol provides subscript access to ReadOnlyFragment objects by index.
protocol ReadOnlyArrayFragment {
    subscript(index: Int) -> ReadOnlyFragment { get }
}


/// ReadOnlyDictionaryFragment protocol provides subscript access to ReadOnlyFragment objects by key.
protocol ReadOnlyDictionaryFragment {
    subscript(key: String) -> ReadOnlyFragment { get }
}


/// ReadOnlyFragment provides readonly access to data value. ReadOnlyFragment also provides
/// subscript access by either key or index to the nested values which are wrapped by
/// ReadOnlyFragment objects.
public class ReadOnlyFragment: ReadOnlyFragmentProtocol,
                               ReadOnlyArrayFragment, ReadOnlyDictionaryFragment
{
    
    /// Gets the fragment value.
    /// The value types are Blob, ReadOnlyArray, ReadOnlyDictionary, Number, or String
    /// based on the underlying data type; or nil if the value is nil.
    public var value: Any? {
        return DataConverter.convertGETValue(_impl.object)
    }
    
    
    /// Gets the value as a string.
    /// Returns nil if the value is nil, or the value is not a string.
    public var string: String? {
        return _impl.string
    }
    
    
    /// Gets the value as an integer.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value is nil or is not a numeric value.
    public var int: Int {
        return _impl.integerValue
    }
    
    
    /// Gets the value as a float.
    /// Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value is nil or is not a numeric value.
    public var float: Float {
        return _impl.floatValue
    }
    
    
    /// Gets the value as a double.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns 0.0 if the value is nil or is not a numeric value.
    public var double: Double {
        return _impl.doubleValue
    }
    
    
    /// Gets the value as a boolean.
    /// Returns true if the value is not nil nor NSNull, and is either `true` or a nonzero number.
    public var boolean: Bool {
        return _impl.booleanValue
    }
    
    
    /// Get the value as a Blob.
    /// Returns nil if the value is nil, or the value is not a Blob.
    public var blob: Blob? {
        return _impl.blob
    }
    
    
    /// Gets the value as an Date.
    /// JSON does not directly support dates, so the actual property value must be a string, which is
    /// then parsed according to the ISO-8601 date format (the default used in JSON.)
    /// Returns nil if the value is nil, is not a string, or is not parseable as a date.
    /// NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
    /// without milliseconds.
    public var date: Date? {
        return _impl.date
    }
    
    
    /// Get the value as a ReadOnlyArrayObject, a mapping object of an array value.
    /// Returns nil if the value is nil, or the value is not an array.
    public var array: ReadOnlyArrayObject? {
        return DataConverter.convertGETValue(_impl.array) as? ReadOnlyArrayObject
    }
    
    
    /// Get a property's value as a ReadOnlyDictionaryObject, a mapping object of a dictionary value.
    /// Returns nil if the value is nil, or the value is not a dictionary.
    public var dictionary: ReadOnlyDictionaryObject? {
        return DataConverter.convertGETValue(_impl.dictionary) as? ReadOnlyDictionaryObject
    }
    
    
    /// Checks whether the value held by the fragment object exists or is nil value or not.
    public var exists: Bool {
        return _impl.exists
    }
    
    
    // MARK: Subscript
    
    
    /// Subscript access to a ReadOnlyFragment object by index.
    ///
    /// - Parameter index: The index
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[UInt(index)])
    }
    
    
    /// Subscript access to a ReadOnlyFragment object by key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    

    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLReadOnlyFragment
    
}
