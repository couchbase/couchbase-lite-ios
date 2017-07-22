//
//  Result.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Result represents a single row in the query result. The projecting result value can be
    accessed either by using a zero based index or by a key corresponding to the
    SelectResult objects given when constructing the Query object.
 
    A key used for accessing the projecting result value could be one of the followings:
    * The alias name of the SelectResult object.
    * The last component of the keypath or property name of the property expression used
      when creating the SelectResult object.
    * The provision key in $1, $2, ...$N format for the SelectResult that doesn't have
      an alias name specified or is not a property expression such as an aggregate function 
      expression (e.g. count(), avg(), min(), max(), sum() and etc). The number suffix 
      after the '$' character is a running number starting from one. */
public class Result : ReadOnlyArrayProtocol, ReadOnlyDictionaryProtocol {
    
    // MARK: ReadOnlyArrayProtocol
    
    /** A number of the projecting values in the result */
    public var count: Int {
        return Int(impl.count)
    }
    
    /** The projecting result value at the given index. */
    public func value(at index: Int) -> Any? {
        return DataConverter.convertGETValue(impl.object(at: UInt(index)))
    }
    
    /** The projecting result value at the given index as a String value. 
        Returns nil if the value is not a string. */
    public func string(at index: Int) -> String? {
        return impl.string(at: UInt(index))
    }
    
    /** The projecting result value at the given index as an Integer value. 
        Returns 0 if the value is not a numeric value. */
    public func int(at index: Int) -> Int {
        return impl.integer(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a Float value. 
        Returns 0.0 if the value is not a numeric value. */
    public func float(at index: Int) -> Float {
        return impl.float(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a Double value. 
        Returns 0.0 if the value is not a numeric value. */
    public func double(at index: Int) -> Double {
        return impl.double(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a Boolean value. 
        Returns true if the value is not null, and is either `true` or a nonzero number. */
    public func boolean(at index: Int) -> Bool {
        return impl.boolean(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a Blob value. 
        Returns nil if the value is not a blob. */
    public func blob(at index: Int) -> Blob? {
        return impl.blob(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a Date value. 
        Returns nil if the value is not a string and is not parseable as a date. */
    public func date(at index: Int) -> Date? {
        return impl.date(at: UInt(index))
    }
    
    /** The projecting result value at the given index as a readonly ArrayObject value. 
        Returns nil if the value is not an array. */
    public func array(at index: Int) -> ReadOnlyArrayObject? {
        return value(at: index) as? ReadOnlyArrayObject
    }
    
    /** The projecting result value at the given index as a readonly DictionaryObject value. 
        Returns nil if the value is not a dictionary. */
    public func dictionary(at index: Int) -> ReadOnlyDictionaryObject? {
        return value(at: index) as? ReadOnlyDictionaryObject
    }
    
    /** All values as a JSON Array object. The values contained in the
        returned Array object are all JSON based values. */
    public func toArray() -> Array<Any> {
        return impl.toArray()
    }
    
    // MARK: ReadOnlyArrayFragment
    
    /** Subscript access to a ReadOnlyFragment object of the projecting result 
        value at the given index. */
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(impl[UInt(index)])
    }
    
    // MARK: ReadOnlyDictionaryProtocol
    
    /** All projecting keys. */
    public var keys: Array<String> {
        return impl.keys
    }
    
    /** The projecting result value for the given key. */
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(impl.object(forKey: key))
    }
    
    /** The projecting result value for the given key as a String value.
        Returns nil if the key doesn't exist, or the value is not a string. */
    public func string(forKey key: String) -> String? {
        return impl.string(forKey: key)
    }
    
    /** The projecting result value for the given key as an Integer value.
        Returns 0 if the key doesn't exist, or the value is not a numeric value. */
    public func int(forKey key: String) -> Int {
        return impl.integer(forKey: key)
    }
    
    /** The projecting result value for the given key as a Float value.
        Returns 0.0 if the key doesn't exist, or the value is not a numeric value. */
    public func float(forKey key: String) -> Float {
        return impl.float(forKey: key)
    }
    
    /** The projecting result value for the given key as a Double value.
        Returns 0.0 if the key doesn't exist, or the value is not a numeric value. */
    public func double(forKey key: String) -> Double {
        return impl.double(forKey: key)
    }
    
    /** The projecting result value for the given key as a Boolean value.
        Returns true if the key doesn't exist, or 
        the value is not null, and is either `true` or a nonzero number. */
    public func boolean(forKey key: String) -> Bool {
        return impl.boolean(forKey: key)
    }
    
    /** The projecting result value for the given key as a Blob value.
        Returns nil if the key doesn't exist, or the value is not a blob. */
    public func blob(forKey key: String) -> Blob? {
        return impl.blob(forKey: key)
    }
    
    /** The projecting result value for the given key as a Date value.
        Returns nil if the key doesn't exist, or 
        the value is not a string and is not parseable as a date. */
    public func date(forKey key: String) -> Date? {
        return impl.date(forKey: key)
    }
    
    /** The projecting result value for the given key as a readonly ArrayObject value.
        Returns nil if the key doesn't exist, or the value is not an array. */
    public func array(forKey key: String) -> ReadOnlyArrayObject? {
        return value(forKey: key) as? ReadOnlyArrayObject
    }
    
    /** The projecting result value for the given key as a readonly DictionaryObject value.
        Returns nil if the key doesn't exist, or the value is not a dictionary. */
    public func dictionary(forKey key: String) -> ReadOnlyDictionaryObject? {
        return value(forKey: key) as? ReadOnlyDictionaryObject
    }
    
    /** Tests whether a projecting result key exists or not. */
    public func contains(_ key: String) -> Bool {
        return impl.containsObject(forKey: key)
    }
    
    /** All values as a JSON Dictionary object. The values contained in the 
        returned Dictionary object are all JSON based values. */
    public func toDictionary() -> Dictionary<String, Any> {
        return impl.toDictionary()
    }
    
    // MARK: Sequence
    
    /** Gets  an iterator over the prjecting result keys. */
    public func makeIterator() -> IndexingIterator<[String]> {
        return impl.keys.makeIterator();
    }
    
    // MARK: ReadOnlyDictionaryFragment
    
    /** Subscript access to a ReadOnlyFragment object of the projecting result
        value for the given key. */
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(impl[key])
    }
    
    // MARK: Internal
    
    private var impl: CBLQueryResult
    
    init(impl: CBLQueryResult) {
        self.impl = impl
    }
}
