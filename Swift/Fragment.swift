//
//  Fragment.swift
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


/// FragmentProtocol provides readonly access to the data value wrapped by a fragment object.
protocol FragmentProtocol {
    var value: Any? { get }
    
    var string: String? { get }
    
    var int: Int { get }
    
    var int64: Int64 { get }
    
    var float: Float { get }
    
    var double: Double { get }
    
    var number: NSNumber? { get }
    
    var boolean: Bool { get }
    
    var date: Date? { get }
    
    var blob: Blob? { get }
    
    var array: ArrayObject? { get }
    
    var dictionary: DictionaryObject? { get }
    
    var exists: Bool { get }
}


/// ArrayFragment protocol provides subscript access to Fragment objects by index.
protocol ArrayFragment {
    subscript(index: Int) -> Fragment { get }
}


/// DictionaryFragment protocol provides subscript access to Fragment objects by key.
protocol DictionaryFragment {
    subscript(key: String) -> Fragment { get }
}


/// Fragment provides readonly access to data value. Fragment also provides
/// subscript access by either key or index to the nested values which are wrapped by
/// Fragment objects.
public class Fragment: FragmentProtocol, ArrayFragment, DictionaryFragment
{
    
    /// Gets the fragment value.
    /// The value types are Blob, Array, Dictionary, Number, or String
    /// based on the underlying data type; or nil if the value is nil.
    public var value: Any? {
        return DataConverter.convertGETValue(_impl.value)
    }
    
    
    /// Gets the value as a string.
    /// Returns nil if the value is nil, or the value is not a string.
    public var string: String? {
        return _impl.string
    }
    
    
    /// Gets the value as an int.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value is nil or is not a numeric value.
    public var int: Int {
        return _impl.integerValue
    }
    
    
    /// Gets the value as an int64.
    /// Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
    /// Returns 0 if the value is nil or is not a numeric value.
    public var int64: Int64 {
        return _impl.longLongValue
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
    
    
    /// Gets the value as a Number.
    /// Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
    /// Returns nil if the value is nil, or the value is not a Number.
    public var number: NSNumber? {
        return _impl.number
    }
    
    
    /// Gets the value as a boolean.
    /// Returns true if the value is not nil nor NSNull, and is either `true` or a nonzero number.
    public var boolean: Bool {
        return _impl.booleanValue
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
    
    
    /// Get the value as a Blob.
    /// Returns nil if the value is nil, or the value is not a Blob.
    public var blob: Blob? {
        return DataConverter.convertGETValue(_impl.blob) as? Blob
    }
    
    
    /// Get the value as a ArrayObject, a mapping object of an array value.
    /// Returns nil if the value is nil, or the value is not an array.
    public var array: ArrayObject? {
        return DataConverter.convertGETValue(_impl.array) as? ArrayObject
    }
    
    
    /// Get a property's value as a DictionaryObject, a mapping object of a dictionary value.
    /// Returns nil if the value is nil, or the value is not a dictionary.
    public var dictionary: DictionaryObject? {
        return DataConverter.convertGETValue(_impl.dictionary) as? DictionaryObject
    }
    
    
    /// Checks whether the value held by the fragment object exists or is nil value or not.
    public var exists: Bool {
        return _impl.exists
    }
    
    
    // MARK: Subscript
    
    
    /// Subscript access to a Fragment object by index.
    ///
    /// - Parameter index: The index
    public subscript(index: Int) -> Fragment {
        return Fragment(_impl[UInt(index)])
    }
    
    
    /// Subscript access to a Fragment object by key.
    ///
    /// - Parameter key: The key.
    public subscript(key: String) -> Fragment {
        return Fragment(_impl[key])
    }
    

    // MARK: Internal
    
    
    init(_ impl: CBLFragment?) {
        _impl = impl ?? Fragment.kNonexistentRO
    }
    
    
    let _impl: CBLFragment


    static let kNonexistentRO = CBLFragment()
    
}
