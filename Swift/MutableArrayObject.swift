//
//  MutableArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** MutableArrayProtocol protocol defines a set of methods for getting and setting array data. */
protocol MutableArrayProtocol: ArrayProtocol, MutableArrayFragment {
    
    // MARK: Type Setters
    
    @discardableResult func setValue(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func setString(_ value: String?, at index: Int) -> Self
    
    @discardableResult func setNumber(_ value: NSNumber?, at index: Int) -> Self
    
    @discardableResult func setInt(_ value: Int, at index: Int) -> Self
    
    @discardableResult func setInt64(_ value: Int64, at index: Int) -> Self
    
    @discardableResult func setFloat(_ value: Float, at index: Int) -> Self
    
    @discardableResult func setDouble(_ value: Double, at index: Int) -> Self
    
    @discardableResult func setBoolean(_ value: Bool, at index: Int) -> Self
    
    @discardableResult func setDate(_ value: Date?, at index: Int) -> Self
    
    @discardableResult func setBlob(_ value: Blob?, at index: Int) -> Self
 
    @discardableResult func setArray(_ value: ArrayObject?, at index: Int) -> Self
    
    @discardableResult func setDictionary(_ value: DictionaryObject?, at index: Int) -> Self
    
    
    // MARK: Type Appenders
    
    @discardableResult func addValue(_ value: Any?) -> Self
    
    @discardableResult func addString(_ value: String?) -> Self
    
    @discardableResult func addNumber(_ value: NSNumber?) -> Self
    
    @discardableResult func addInt(_ value: Int) -> Self
    
    @discardableResult func addInt64(_ value: Int64) -> Self
    
    @discardableResult func addFloat(_ value: Float) -> Self
    
    @discardableResult func addDouble(_ value: Double) -> Self
    
    @discardableResult func addBlob(_ value: Blob?) -> Self
    
    @discardableResult func addBoolean(_ value: Bool) -> Self
    
    @discardableResult func addDate(_ value: Date?) -> Self
    
    @discardableResult func addArray(_ value: ArrayObject?) -> Self
    
    @discardableResult func addDictionary(_ value: DictionaryObject?) -> Self
    
    // MARK: Type Inserters
    
    @discardableResult func insertValue(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func insertString(_ value: String?, at index: Int) -> Self
    
    @discardableResult func insertNumber(_ value: NSNumber?, at index: Int) -> Self
    
    @discardableResult func insertInt(_ value: Int, at index: Int) -> Self
    
    @discardableResult func insertInt64(_ value: Int64, at index: Int) -> Self
    
    @discardableResult func insertFloat(_ value: Float, at index: Int) -> Self
    
    @discardableResult func insertDouble(_ value: Double, at index: Int) -> Self
    
    @discardableResult func insertBoolean(_ value: Bool, at index: Int) -> Self
    
    @discardableResult func insertDate(_ value: Date?, at index: Int) -> Self
    
    @discardableResult func insertBlob(_ value: Blob?, at index: Int) -> Self
    
    @discardableResult func insertArray(_ value: ArrayObject?, at index: Int) -> Self
    
    @discardableResult func insertDictionary(_ value: DictionaryObject?, at index: Int) -> Self
    
    // MARK: Data
    
    @discardableResult func setData(_ data: Array<Any>?) -> Self
    
    // MARK: Removing Value
    
    @discardableResult func removeValue(at index: Int) -> Self
    
    // MARK: Getting MutableArrayObject and MutableDictionaryObject
    
    func array(at index: Int) -> MutableArrayObject? /* override */
    
    func dictionary(at index: Int) -> MutableDictionaryObject? /* override */
}

/** MutableArrayObject provides access to array data. */
public final class MutableArrayObject: ArrayObject, MutableArrayProtocol {
    
    // MARK: Initializers
    
    
    /// Initialize a new empty MutableArrayObject.
    public init() {
        super.init(CBLMutableArray())
    }
    
    
    /// Initialize a new MutableArrayObject object with the data. Allowed
    /// value types are Array, ArrayObject, Blob, Date, Dictionary,
    /// DictionaryObject, NSNull, Number types, and String.
    /// The Arrays and Dictionaries must contain only the above types.
    ///
    /// - Parameter array: The array object.
    public init(withData data: Array<Any>?) {
        super.init(CBLMutableArray())
        setData(data)
    }
    
    
    // MARK: Type Setters
    
    
    /// Sets a value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setValue(_ value: Any?, at index: Int) -> Self {
        arrayImpl.setValue(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /// Sets a String object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The String object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setString(_ value: String?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a Number value at the given index.
    ///
    /// - Parameters:
    ///   - value: The Number value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setNumber(_ value: NSNumber?, at index: Int) -> Self {
        return setValue(value, at: index);
    }
    
    
    /// Sets an int value at the given index.
    ///
    /// - Parameters:
    ///   - value: The int value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setInt(_ value: Int, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets an int64 value at the given index.
    ///
    /// - Parameters:
    ///   - value: The int64 value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setInt64(_ value: Int64, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a float value at the given index.
    ///
    /// - Parameters:
    ///   - value: The float value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setFloat(_ value: Float, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a double value at the given index.
    ///
    /// - Parameters:
    ///   - value: The double value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setDouble(_ value: Double, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a boolean value at the given index.
    ///
    /// - Parameters:
    ///   - value: The boolean value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setBoolean(_ value: Bool, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a Date object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Date object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setDate(_ value: Date?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a Blob object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Blob object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setBlob(_ value: Blob?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets an ArrayObject object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The ArrayObject object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setArray(_ value: ArrayObject?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    /// Sets a DictionaryObject object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The DictionaryObject object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func setDictionary(_ value: DictionaryObject?, at index: Int) -> Self {
        return setValue(value, at: index)
    }
    
    
    // MARK: Type Appenders
    
    
    /// Adds a value to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The value.
    /// - Returns: The self object.
    @discardableResult public func addValue(_ value: Any?) -> Self {
        arrayImpl.addValue(DataConverter.convertSETValue(value))
        return self
    }
    
    
    /// Adds a String object to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The String object.
    /// - Returns: The self object.
    @discardableResult public func addString(_ value: String?) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a Number value to the end of the array.
    ///
    /// - Parameter value: The Number value.
    /// - Returns: The self object.
    @discardableResult public func addNumber(_ value: NSNumber?) -> Self {
        return addValue(value)
    }
    
    
    /// Adds an int value to the end of the array.
    ///
    /// - Parameter value: The int value.
    /// - Returns: The ArrayObject object.
    @discardableResult public func addInt(_ value: Int) -> Self {
        return addValue(value)
    }
    
    
    /// Adds an int64 value to the end of the array.
    ///
    /// - Parameter value: The int64 value.
    /// - Returns: The self object.
    @discardableResult public func addInt64(_ value: Int64) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a float value to the end of the array.
    ///
    /// - Parameter value: The double value.
    /// - Returns: The self object.
    @discardableResult public func addFloat(_ value: Float) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a double value to the end of the array.
    ///
    /// - Parameter value: The double value.
    /// - Returns: The self object.
    @discardableResult public func addDouble(_ value: Double) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a boolean value to the end of the array.
    ///
    /// - Parameter value: The boolean value.
    /// - Returns: The self object.
    @discardableResult public func addBoolean(_ value: Bool) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a Date object to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The Date object.
    /// - Returns: The self object.
    @discardableResult public func addDate(_ value: Date?) -> Self {
        return addValue(value)
    }

    
    /// Adds a Blob object to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The Blob object.
    /// - Returns: The self object.
    @discardableResult public func addBlob(_ value: Blob?) -> Self {
        return addValue(value)
    }
    
    /// Adds an ArrayObject object to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The ArrayObject object.
    /// - Returns: The self object.
    @discardableResult public func addArray(_ value: ArrayObject?) -> Self {
        return addValue(value)
    }
    
    
    /// Adds a Dictionary object to the end of the array. A nil value will be converted to an NSNull.
    ///
    /// - Parameter value: The Dictionary object.
    /// - Returns: The self object.
    @discardableResult public func addDictionary(_ value: DictionaryObject?) -> Self {
        return addValue(value)
    }
    
    
    // MARK: Type Inserters
    
    
    /// Inserts a value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertValue(_ value: Any?, at index: Int) -> Self {
        arrayImpl.insertValue(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    /// Inserts a String object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The String object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertString(_ value: String?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a Number value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The number value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertNumber(_ value: NSNumber?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts an int value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The int value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertInt(_ value: Int, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts an int64 value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The int64 value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertInt64(_ value: Int64, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a float value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The float value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertFloat(_ value: Float, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a double value at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The double value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertDouble(_ value: Double, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a boolean value at the given index.
    ///
    /// - Parameters:
    ///   - value: The boolean value.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertBoolean(_ value: Bool, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a Date object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Date object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertDate(_ value: Date?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a Blob object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Blob object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertBlob(_ value: Blob?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts an ArrayObject at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The ArrayObject object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertArray(_ value: ArrayObject?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    /// Inserts a Dictionary object at the given index. A nil value will be converted to an NSNull.
    ///
    /// - Parameters:
    ///   - value: The Dictionary object.
    ///   - index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func insertDictionary(_ value: DictionaryObject?, at index: Int) -> Self {
        return insertValue(value, at: index)
    }
    
    
    // MARK: Removing Value
    
    
    /// Removes the object at the given index.
    ///
    /// - Parameter index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The self object.
    @discardableResult public func removeValue(at index: Int) -> Self {
        arrayImpl.removeValue(at: UInt(index))
        return self
    }
    
    
    // MARK: Data
    

    /// Set data for the array. Allowed value types are Array, ArrayObject,
    /// Blob, Date, Dictionary, DictionaryObject, NSNull, Number types, and String.
    /// The Arrays and Dictionaries must contain only the above types.
    ///
    /// - Parameter array: The array.
    /// - Returns: The self object.
    @discardableResult public func setData(_ data: Array<Any>?) -> Self {
        arrayImpl.setData(DataConverter.convertSETArray(data))
        return self
    }
    
    
    // MARK: Getting ArrayObject and DictionaryObject
    
    
    /// Gets an MutableArrayObject at the given index. Returns nil if the value is not an array.
    ///
    /// - Parameter index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The ArrayObject object.
    public override func array(at index: Int) -> MutableArrayObject? {
        return value(at: index) as? MutableArrayObject
    }
    
    
    /// Gets a MutableDictionaryObject at the given index. Returns nil if the value is not a dictionary.
    ///
    /// - Parameter index: The index. This value must not exceed the bounds of the array.
    /// - Returns: The MutableDictionaryObject object.
    public override func dictionary(at index: Int) -> MutableDictionaryObject? {
        return value(at: index) as? MutableDictionaryObject
    }
    
    
    // MARK: ArrayFragment
    
    
    /// Subscripting access to a MutableFragment object that represents the value at the given index.
    ///
    /// - Parameter index: The index. If the index value exceeds the bounds of the array,
    ///                    the MutableFragment object will represent a nil value.
    /// - Returns: The Fragment object.
    public override subscript(index: Int) -> MutableFragment {
        return MutableFragment(arrayImpl[UInt(index)])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLMutableArray) {
        super.init(impl)
    }
    
    
    // MARK: Private
    
    
    private var arrayImpl: CBLMutableArray {
        return _impl as! CBLMutableArray
    }
    
}
