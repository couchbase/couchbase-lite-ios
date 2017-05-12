//
//  ReadOnlyArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol ReadOnlyArrayProtocol {
    var count: Int { get }
    
    func getValue(_ index: Int) -> Any?
    
    func getString(_ index: Int) -> String?
    
    func getInt(_ index: Int) -> Int
    
    func getFloat(_ index: Int) -> Float
    
    func getDouble(_ index: Int) -> Double
    
    func getBoolean(_ index: Int) -> Bool
    
    func getBlob(_ index: Int) -> Blob?
    
    func getDate(_ index: Int) -> Date?
    
    func getArray(_ index: Int) -> ReadOnlyArrayObject?
    
    func getDictionary(_ index: Int) -> ReadOnlyDictionaryObject?
    
    func toArray() -> Array<Any>
}

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
