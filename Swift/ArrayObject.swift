//
//  ArrayObject.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol ArrayProtocol: ReadOnlyArrayProtocol {
    @discardableResult func setArray(_ array: Array<Any>?) -> Self
    
    @discardableResult func set(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func add(_ value: Any?) -> Self
    
    @discardableResult func insert(_ value: Any?, at index: Int) -> Self
    
    @discardableResult func remove(_ index: Int) -> Self
    
    /* override */ func getArray(_ index: Int) -> ArrayObject?
    
    /* override */ func getDictionary(_ index: Int) -> DictionaryObject?
}

public class ArrayObject: ReadOnlyArrayObject, ArrayProtocol {
    public init() {
        super.init(CBLArray())
    }
    
    
    public init(array: Array<Any>?) {
        super.init(CBLArray())
        setArray(array)
    }
    
    
    @discardableResult public func setArray(_ array: Array<Any>?) -> Self {
        arrayImpl.setArray(DataConverter.convertSETArray(array))
        return self
    }
    
    
    @discardableResult public func set(_ value: Any?, at index: Int) -> Self {
        arrayImpl.setObject(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    @discardableResult public func add(_ value: Any?) -> Self {
        arrayImpl.add(DataConverter.convertSETValue(value))
        return self
    }
    
    
    @discardableResult public func insert(_ value: Any?, at index: Int) -> Self {
        arrayImpl.insert(DataConverter.convertSETValue(value), at: UInt(index))
        return self
    }
    
    
    @discardableResult public func remove(_ index: Int) -> Self {
        arrayImpl.removeObject(at: UInt(index))
        return self
    }
    
    
    public override func getArray(_ index: Int) -> ArrayObject? {
        return getValue(index) as? ArrayObject
    }
    
    
    public override func getDictionary(_ index: Int) -> DictionaryObject? {
        return getValue(index) as? DictionaryObject
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
