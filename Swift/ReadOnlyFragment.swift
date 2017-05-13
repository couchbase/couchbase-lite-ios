//
//  ReadOnlyFragment.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/8/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

protocol ReadOnlyFragmentProtocol {
    var value: Any? { get }
    
    var string: String? { get }
    
    var int: Int { get }
    
    var float: Float { get }
    
    var double: Double { get }
    
    var boolean: Bool { get }
    
    var date: Date? { get }
    
    var array: ReadOnlyArrayObject? { get }
    
    var dictionary: ReadOnlyDictionaryObject? { get }
    
    var exists: Bool { get }
}


protocol ReadOnlyDictionaryFragment {
    subscript(key: String) -> ReadOnlyFragment { get }
}


protocol ReadOnlyArrayFragment {
    subscript(index: Int) -> ReadOnlyFragment { get }
}


public class ReadOnlyFragment: ReadOnlyFragmentProtocol,
                               ReadOnlyDictionaryFragment, ReadOnlyArrayFragment
{
    public var value: Any? {
        return DataConverter.convertGETValue(_impl.object)
    }
    
    
    public var string: String? {
        return _impl.string
    }
    
    
    public var int: Int {
        return _impl.integerValue
    }
    
    
    public var float: Float {
        return _impl.floatValue
    }
    
    
    public var double: Double {
        return _impl.doubleValue
    }
    
    
    public var boolean: Bool {
        return _impl.booleanValue
    }
    
    
    public var date: Date? {
        return _impl.date
    }
    
    
    public var array: ReadOnlyArrayObject? {
        return DataConverter.convertGETValue(_impl.array) as? ReadOnlyArrayObject
    }
    
    
    public var dictionary: ReadOnlyDictionaryObject? {
        return DataConverter.convertGETValue(_impl.dictionary) as? ReadOnlyDictionaryObject
    }
    
    
    public var exists: Bool {
        return _impl.exists
    }
    
    
    // MARK: ReadOnlyDictionaryFragment
    
    
    public subscript(key: String) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[key])
    }
    
    
    // MARK: ReadOnlyArrayFragment
    
    
    public subscript(index: Int) -> ReadOnlyFragment {
        return ReadOnlyFragment(_impl[UInt(index)])
    }
    

    // MARK: Internal
    
    
    init(_ impl: CBLReadOnlyFragment) {
        _impl = impl
    }
    
    
    let _impl: CBLReadOnlyFragment
}
