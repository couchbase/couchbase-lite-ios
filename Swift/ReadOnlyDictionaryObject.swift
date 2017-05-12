//
//  ReadOnlyDictionaryObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol ReadOnlyDictionaryProtocol: ReadOnlyDictionaryFragment {
    var count: Int { get }
    
    func getValue(_ key: String) -> Any?
    
    func getString(_ key: String) -> String?
    
    func getInt(_ key: String) -> Int
    
    func getFloat(_ key: String) -> Float
    
    func getDouble(_ key: String) -> Double
    
    func getBoolean(_ key: String) -> Bool
    
    func getBlob(_ key: String) -> Blob?
    
    func getDate(_ key: String) -> Date?
    
    func getArray(_ key: String) -> ReadOnlyArrayObject?
    
    func getDictionary(_ key: String) -> ReadOnlyDictionaryObject?
    
    func toDictionary() -> Dictionary<String, Any>
    
    func contains(_ key: String) -> Bool
}

public class ReadOnlyDictionaryObject: ReadOnlyDictionaryProtocol {
    public var count: Int {
        return Int(_impl.count)
    }
    
    public func getValue(_ key: String) -> Any? {
        return DataConverter.convertGETValue(_impl.object(forKey: key))
    }
    
    
    public func getString(_ key: String) -> String? {
        return _impl.string(forKey: key)
    }
    
    
    public func getInt(_ key: String) -> Int {
        return _impl.integer(forKey: key)
    }
    
    
    public func getFloat(_ key: String) -> Float {
        return _impl.float(forKey: key)
    }
    
    
    public func getDouble(_ key: String) -> Double {
        return _impl.double(forKey: key)
    }
    
    
    public func getBoolean(_ key: String) -> Bool {
        return _impl.boolean(forKey: key)
    }
    
    
    public func getBlob(_ key: String) -> Blob? {
        return _impl.blob(forKey: key)
    }
    
    
    public func getDate(_ key: String) -> Date? {
        return _impl.date(forKey: key)
    }
    
    
    public func getArray(_ key: String) -> ReadOnlyArrayObject? {
        return getValue(key) as? ReadOnlyArrayObject
    }
    
    
    public func getDictionary(_ key: String) -> ReadOnlyDictionaryObject? {
        return getValue(key) as? ReadOnlyDictionaryObject
    }
    
    
    public func toDictionary() -> Dictionary<String, Any> {
        return _impl.toDictionary()
    }
    
    
    public func contains(_ key: String) -> Bool {
        return _impl.containsObject(forKey: key)
    }
    
    
    // MARK: ReadOnlyDictionaryFragment
    
    
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    
    
    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyDictionary) {
        _impl = impl
        _impl.swiftObject = self
    }
    
    
    deinit {
        _impl.swiftObject = nil
    }
    
    
    let _impl: CBLReadOnlyDictionary
}
