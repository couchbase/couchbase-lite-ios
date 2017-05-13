//
//  ArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// ArrayProtocol protocol defines a set of methods for getting and setting array data.
protocol ArrayProtocol: ReadOnlyArrayProtocol, ArrayFragment {
    /// Set an array as a content. Allowed value types are Array, Date, Dictionary, Number,
    /// NSNull, String, ArrayObject, Blob, DictionaryObject. The Array and Dictionary must
    /// contain only the above types. Setting the new array content will replace the current data
    /// including the existing ArrayObject and DictionaryObject objects.
    /// - Parameter array: the array.
    /// - Returns: the ArrayProtocol object. */
    @discardableResult func setArray(_ array: Array<Any>?) -> Self
    
    /// Sets an object at the given index. Setting a nil value is eqivalent
    /// to setting an NSNull object.
    /// - Parameter object: the object.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayProtocol object.
    @discardableResult func set(_ value: Any?, at index: Int) -> Self
    
    /// Adds an object to the end of the array. Adding a nil value is equivalent
    /// to adding an NSNull object.
    /// - Parameter object: the object.
    /// - Returns: the ArrayProtocol object.
    @discardableResult func add(_ value: Any?) -> Self
    
    /// Inserts an object at the given index. Inserting a nil value is equivalent
    /// to inserting an NSNull object.
    /// - Parameter object: the object.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayProtocol object.
    @discardableResult func insert(_ value: Any?, at index: Int) -> Self
    
    /// Removes the object at the given index.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayProtocol object.
    @discardableResult func remove(_ index: Int) -> Self
    
    /// Gets an ArrayObject at the given index. Returns nil if the value is not an array.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayObject.
    /* override */ func getArray(_ index: Int) -> ArrayObject?
    
    /// Gets a DictionaryObject at the given index. Returns nil if the value is not a dictionary.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the DictionaryObject object.
    /* override */ func getDictionary(_ index: Int) -> DictionaryObject?
}

/// ArrayObject provides access to array data.
public class ArrayObject: ReadOnlyArrayObject, ArrayProtocol {
    /// Initialize a new empty CBLArray object.
    public init() {
        super.init(CBLArray())
    }
    
    
    /// Initialize a new ArrayObject object with an array content. Allowed value types are NSArray,
    /// NSDate, NSDictionary, NSNumber, NSNull, NSString, ArrayObject, CBLBlob, DictionaryObject.
    /// The NSArrays and NSDictionaries must contain only the above types.
    /// - Parameter array: the array object.
    public init(array: Array<Any>?) {
        super.init(CBLArray())
        setArray(array)
    }
    
    
    /// Set an array as a content. Allowed value types are Array, Date, Dictionary, Number,
    /// NSNull, String, ArrayObject, Blob, DictionaryObject. The Array and Dictionary must
    /// contain only the above types. Setting the new array content will replace the current data
    /// including the existing ArrayObject and DictionaryObject objects.
    /// - Parameter array: the array.
    /// - Returns: the ArrayObject object. */
    @discardableResult public func setArray(_ array: Array<Any>?) -> Self {
        arrayImpl.setArray(DataConverter.convertSETArray(array))
        return self
    }
    
    
    /// Sets an object at the given index. Setting a nil value is eqivalent
    /// to setting an NSNull object.
    /// - Parameter object: the object.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayObject object.
    @discardableResult public func set(_ value: Any?, at index: Int) -> Self {
        arrayImpl.setObject(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /// Adds an object to the end of the array. Adding a nil value is equivalent
    /// to adding an NSNull object.
    /// - Parameter object: the object.
    /// - Returns: the ArrayObject object.
    @discardableResult public func add(_ value: Any?) -> Self {
        arrayImpl.add(DataConverter.convertSETValue(value))
        return self
    }
    
    
    /// Inserts an object at the given index. Inserting a nil value is equivalent
    /// to inserting an NSNull object.
    /// - Parameter object: the object.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayObject object.
    @discardableResult public func insert(_ value: Any?, at index: Int) -> Self {
        arrayImpl.insert(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /// Removes the object at the given index.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayObject object.
    @discardableResult public func remove(_ index: Int) -> Self {
        arrayImpl.removeObject(at: UInt(index))
        return self
    }
    
    
    /// Gets an ArrayObject at the given index. Returns nil if the value is not an array.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the ArrayObject.
    public override func getArray(_ index: Int) -> ArrayObject? {
        return getValue(index) as? ArrayObject
    }
    
    
    /// Gets a DictionaryObject at the given index. Returns nil if the value is not a dictionary.
    /// - Parameter index: the index. This value must not exceed the bounds of the array.
    /// - Returns: the DictionaryObject object.
    public override func getDictionary(_ index: Int) -> DictionaryObject? {
        return getValue(index) as? DictionaryObject
    }
    
    
    // MARK: ArrayFragment
    
    
    /// Subscripting access to a Fragment object that represents the value at the given index.
    /// - Parameter index: the index. If the index value exceeds the bounds of the array, 
    ///   the Fragment object will represent a nil value.
    /// - Returns: the CBLFragment object. */
    public override subscript(index: Int) -> Fragment {
        return Fragment(arrayImpl[UInt(index)])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLArray) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var arrayImpl: CBLArray {
        return _impl as! CBLArray
    }
    
}
