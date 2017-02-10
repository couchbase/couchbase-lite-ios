//
//  Properties.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


public class Properties {

    public var properties : [String:Any]? {
        get {return _impl.properties}
        set {_impl.properties = newValue}
    }


    public func property(_ key: String) -> Any? {
        return _impl.object(forKey: key)
    }

    public func setProperty(_ key: String, _ value: Any?) {
        return _impl.setObject(value, forKey: key)
    }


    public func contains(_ key: String) -> Bool {
        return _impl.containsObject(forKey: key)
    }

    
    public subscript(key: String) -> Bool {
        get {return _impl.boolean(forKey: key)}
        set {_impl.setBoolean(newValue, forKey: key)}
    }

    public subscript(key: String) -> Int {
        get {return _impl.integer(forKey: key)}
        set {_impl.setInteger(newValue, forKey: key)}
    }

    public subscript(key: String) -> Float {
        get {return _impl.float(forKey: key)}
        set {_impl.setFloat(newValue, forKey: key)}
    }

    public subscript(key: String) -> Double {
        get {return _impl.double(forKey: key)}
        set {_impl.setDouble(newValue, forKey: key)}
    }

    public subscript(key: String) -> String? {
        get {return _impl.string(forKey: key)}
    }

    public subscript(key: String) -> Date? {
        get {return _impl.date(forKey: key)}
    }

    public subscript(key: String) -> Blob? {
        get {return _impl.object(forKey: key) as? Blob}
    }

    public subscript(key: String) -> [Any]? {
        get {return _impl.object(forKey: key) as? [Any]}
    }

    public subscript(key: String) -> [String:Any]? {
        get {return _impl.object(forKey: key) as? [String:Any]}
    }

    public subscript(key: String) -> Any? {
        get {return _impl.object(forKey: key)}
        set {_impl.setObject(newValue, forKey: key)}
    }


    init(_ impl: CBLProperties) {
        _impl = impl
    }

    let _impl: CBLProperties
}


public typealias Blob = CBLBlob
