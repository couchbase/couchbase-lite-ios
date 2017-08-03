//
//  ArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** ArrayProtocol protocol defines a set of methods for getting and setting array data. */
protocol ArrayProtocol: ReadOnlyArrayProtocol, ArrayFragment {
    
    // MARK: Type Setters
    
    @discardableResult func setArray(_ value: ArrayObject?, at index: Int) -> Self
    
    @discardableResult func setBlob(_ value: Blob?, at index: Int) -> Self
    
    @discardableResult func setBoolean(_ value: Bool, at index: Int) -> Self
    
    @discardableResult func setDate(_ value: Date?, at index: Int) -> Self
    
    @discardableResult func setDictionary(_ value: DictionaryObject?, at index: Int) -> Self
    
    @discardableResult func setDouble(_ value: Double, at index: Int) -> Self
    
    @discardableResult func setFloat(_ value: Float, at index: Int) -> Self
    
    @discardableResult func setInteger(_ value: Int, at index: Int) -> Self
    
    @discardableResult func setValue(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func setString(_ value: String?, at index: Int) -> Self
    
    // MARK: Type Appenders
    
    @discardableResult func addArray(_ value: ArrayObject?) -> Self
    
    @discardableResult func addBlob(_ value: Blob?) -> Self
    
    @discardableResult func addBoolean(_ value: Bool) -> Self
    
    @discardableResult func addDate(_ value: Date?) -> Self
    
    @discardableResult func addDictionary(_ value: DictionaryObject?) -> Self
    
    @discardableResult func addDouble(_ value: Double) -> Self
    
    @discardableResult func addFloat(_ value: Float) -> Self
    
    @discardableResult func addInteger(_ value: Int) -> Self
    
    @discardableResult func addValue(_ value: Any?) -> Self
    
    @discardableResult func addString(_ value: String?) -> Self
    
    // MARK: Type Inserters
    
    @discardableResult func insertArray(_ value: ArrayObject?, at index: Int) -> Self
    
    @discardableResult func insertBlob(_ value: Blob?, at index: Int) -> Self
    
    @discardableResult func insertBoolean(_ value: Bool, at index: Int) -> Self
    
    @discardableResult func insertDate(_ value: Date?, at index: Int) -> Self
    
    @discardableResult func insertDictionary(_ value: DictionaryObject?, at index: Int) -> Self
    
    @discardableResult func insertDouble(_ value: Double, at index: Int) -> Self
    
    @discardableResult func insertFloat(_ value: Float, at index: Int) -> Self
    
    @discardableResult func insertInteger(_ value: Int, at index: Int) -> Self
    
    @discardableResult func insertValue(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func insertString(_ value: String?, at index: Int) -> Self
    
    // MARK: Removing Value
    
    @discardableResult func remove(at index: Int) -> Self
    
    // MARK: Setting content with an NSArray
    
    @discardableResult func setArray(_ array: Array<Any>?) -> Self
    
    // MARK: Getting ArrayObject and DictionaryObject
    
    func array(at index: Int) -> ArrayObject? /* override */
    
    func dictionary(at index: Int) -> DictionaryObject? /* override */
}

/** ArrayObject provides access to array data. */
public class ArrayObject: ReadOnlyArrayObject, ArrayProtocol {
    
    // MARK: Initializers
    
    
    /** Initialize a new empty CBLArray object. */
    public init() {
        super.init(CBLArray())
    }
    
    
    /** Initialize a new ArrayObject object with an array content. Allowed value types are NSArray,
        NSDate, NSDictionary, NSNumber, NSNull, NSString, ArrayObject, CBLBlob, DictionaryObject.
        The NSArrays and NSDictionaries must contain only the above types.
        - Parameter array: The array object. */
    public init(array: Array<Any>?) {
        super.init(CBLArray())
        setArray(array)
    }
    
    
    // MARK: Type Setters
    
    
    /** Sets an ArrayObject object at the given index. A nil value will be converted to an NSNull.
        - Parameter value: The ArrayObject object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setArray(_ value: ArrayObject?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a Blob object at the given index. A nil value will be converted to an NSNull.
        - Parameter value: The Blob object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setBlob(_ value: Blob?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a boolean value at the given index.
        - Parameter value: The boolean value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setBoolean(_ value: Bool, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a Date object at the given index. A nil value will be converted to an NSNull.
        - Parameter value: The Date object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setDate(_ value: Date?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a DictionaryObject object at the given index. A nil value will be converted to an NSNull.
        - Parameter value: The DictionaryObject object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setDictionary(_ value: DictionaryObject?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a double value at the given index.
        - Parameter value: The double value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setDouble(_ value: Double, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets a float value at the given index.
        - Parameter value: The float value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setFloat(_ value: Float, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets an integer value at the given index.
        - Parameter value: The integer value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setInteger(_ value: Int, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /** Sets an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: the object.
        - Parameter index: the index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setValue(_ value: Any?, at index: Int) -> Self {
        arrayImpl.setObject(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /** Sets a String object at the given index. A nil value will be converted to an NSNull.
        - Parameter value: The String object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func setString(_ value: String?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    // MARK: Type Appenders
    
    
    /** Adds an ArrayObject object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The ArrayObject object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addArray(_ value: ArrayObject?) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a Blob object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The Blob object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addBlob(_ value: Blob?) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a boolean value to the end of the array.
        - Parameter object: The boolean value.
        - Returns: The ArrayObject object. */
    @discardableResult public func addBoolean(_ value: Bool) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a Date object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The Date object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addDate(_ value: Date?) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a Dictionary object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The Dictionary object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addDictionary(_ value: DictionaryObject?) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a double value to the end of the array.
        - Parameter object: The double value.
        - Returns: The ArrayObject object. */
    @discardableResult public func addDouble(_ value: Double) -> Self {
        return addValue(value)
    }
    
    
    /** Adds a float value to the end of the array.
        - Parameter object: The double value.
        - Returns: The ArrayObject object. */
    @discardableResult public func addFloat(_ value: Float) -> Self {
        return addValue(value)
    }
    
    
    /** Adds an integer value to the end of the array.
        - Parameter object: The integer value.
        - Returns: The ArrayObject object. */
    @discardableResult public func addInteger(_ value: Int) -> Self {
        return addValue(value)
    }
    
    
    /** Adds an object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addValue(_ value: Any?) -> Self {
        arrayImpl.add(DataConverter.convertSETValue(value))
        return self
    }
    
    
    /** Adds a String object to the end of the array. A nil value will be converted to an NSNull.
        - Parameter object: The String object.
        - Returns: The ArrayObject object. */
    @discardableResult public func addString(_ value: String?) -> Self {
        return addValue(value)
    }
    
    
    // MARK: Type Inserters
    
    
    /** Inserts an ArrayObject at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The ArrayObject object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertArray(_ value: ArrayObject?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertBlob(_ value: Blob?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    @discardableResult public func insertBoolean(_ value: Bool, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertDate(_ value: Date?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertDictionary(_ value: DictionaryObject?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts a double value at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The double value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertDouble(_ value: Double, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts a float value at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The float value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertFloat(_ value: Float, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts an integer value at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The integer value.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertInteger(_ value: Int, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /** Inserts an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertValue(_ value: Any?, at index: Int) -> Self {
        arrayImpl.insert(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /** Inserts an object at the given index. A nil value will be converted to an NSNull.
        - Parameter object: The object.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func insertString(_ value: String?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    // MARK: Removing Value
    
    
    /** Removes the object at the given index.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject object. */
    @discardableResult public func remove(at index: Int) -> Self {
        arrayImpl.removeObject(at: UInt(index))
        return self
    }
    
    
    // MARK: Setting content with an NSArray
    
    /** Set an array as a content. Allowed value types are Array, Date, Dictionary, Number,
     NSNull, String, ArrayObject, Blob, DictionaryObject. The Array and Dictionary must
     contain only the above types. Setting the new array content will replace the current data
     including the existing ArrayObject and DictionaryObject objects.
     - Parameter array: The array.
     - Returns: The ArrayObject object. */
    @discardableResult public func setArray(_ array: Array<Any>?) -> Self {
        arrayImpl.setArray(DataConverter.convertSETArray(array))
        return self
    }
    
    
    // MARK: Getting ArrayObject and DictionaryObject
    
    
    /** Gets an ArrayObject at the given index. Returns nil if the value is not an array.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The ArrayObject. */
    public override func array(at index: Int) -> ArrayObject? {
        return value(at: index) as? ArrayObject
    }
    
    
    /** Gets a DictionaryObject at the given index. Returns nil if the value is not a dictionary.
        - Parameter index: The index. This value must not exceed the bounds of the array.
        - Returns: The DictionaryObject object. */
    public override func dictionary(at index: Int) -> DictionaryObject? {
        return value(at: index) as? DictionaryObject
    }
    
    
    // MARK: ArrayFragment
    
    
    /** Subscripting access to a Fragment object that represents the value at the given index.
        - Parameter index: The index. If the index value exceeds the bounds of the array,
          the Fragment object will represent a nil value.
        - Returns: The CBLFragment object. */
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
