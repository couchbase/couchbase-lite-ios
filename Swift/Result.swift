//
//  Result.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public class Result : ReadOnlyArrayProtocol, ReadOnlyDictionaryProtocol {
    
    // MARK: ReadOnlyArrayProtocol
    
    public var count: Int {
        return Int(impl.count)
    }
    
    public func value(at index: Int) -> Any? {
        return DataConverter.convertGETValue(impl.object(at: UInt(index)))
    }
    
    public func string(at index: Int) -> String? {
        return impl.string(at: UInt(index))
    }
    
    public func int(at index: Int) -> Int {
        return impl.integer(at: UInt(index))
    }
    
    public func float(at index: Int) -> Float {
        return impl.float(at: UInt(index))
    }
    
    public func double(at index: Int) -> Double {
        return impl.double(at: UInt(index))
    }
    
    public func boolean(at index: Int) -> Bool {
        return impl.boolean(at: UInt(index))
    }
    
    public func blob(at index: Int) -> Blob? {
        return impl.blob(at: UInt(index))
    }
    
    public func date(at index: Int) -> Date? {
        return impl.date(at: UInt(index))
    }
    
    public func array(at index: Int) -> ReadOnlyArrayObject? {
        return value(at: index) as? ReadOnlyArrayObject
    }
    
    public func dictionary(at index: Int) -> ReadOnlyDictionaryObject? {
        return value(at: index) as? ReadOnlyDictionaryObject
    }
    
    public func toArray() -> Array<Any> {
        return impl.toArray()
    }
    
    // MARK: ReadOnlyArrayFragment
    
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(impl[UInt(index)])
    }
    
    // MARK: ReadOnlyDictionaryProtocol
    
    public var keys: Array<String> {
        return impl.keys
    }
    
    public func value(forKey key: String) -> Any? {
        return DataConverter.convertGETValue(impl.object(forKey: key))
    }
    
    public func string(forKey key: String) -> String? {
        return impl.string(forKey: key)
    }
    
    public func int(forKey key: String) -> Int {
        return impl.integer(forKey: key)
    }
    
    public func float(forKey key: String) -> Float {
        return impl.float(forKey: key)
    }
    
    public func double(forKey key: String) -> Double {
        return impl.double(forKey: key)
    }
    
    public func boolean(forKey key: String) -> Bool {
        return impl.boolean(forKey: key)
    }
    
    public func blob(forKey key: String) -> Blob? {
        return impl.blob(forKey: key)
    }
    
    public func date(forKey key: String) -> Date? {
        return impl.date(forKey: key)
    }
    
    public func array(forKey key: String) -> ReadOnlyArrayObject? {
        return value(forKey: key) as? ReadOnlyArrayObject
    }
    
    public func dictionary(forKey key: String) -> ReadOnlyDictionaryObject? {
        return value(forKey: key) as? ReadOnlyDictionaryObject
    }
    
    public func contains(_ key: String) -> Bool {
        return impl.containsObject(forKey: key)
    }
    
    public func toDictionary() -> Dictionary<String, Any> {
        return impl.toDictionary()
    }
    
    // MARK: Sequence
    
    public func makeIterator() -> IndexingIterator<[String]> {
        return impl.keys.makeIterator();
    }
    
    // MARK: ReadOnlyDictionaryFragment
    
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(impl[key])
    }
    
    // MARK: Internal
    
    private var impl: CBLQueryResult
    
    init(impl: CBLQueryResult) {
        self.impl = impl
    }
}
