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
        get {return convertValue(_impl.properties, isGetter: YES) as? [String: Any]}
        set {_impl.properties = convertValue(newValue, isGetter: NO) as? [String : Any]}
    }

    public func property(_ key: String) -> Any? {
        return convertValue(_impl.object(forKey: key), isGetter: YES)
    }

    public func setProperty(_ key: String, _ value: Any?) {
        return _impl.setObject(convertValue(value, isGetter: NO), forKey: key)
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
    
    public subscript(key: String) -> Subdocument? {
        get {return convertValue(_impl.object(forKey: key), isGetter: YES) as? Subdocument}
    }
    
    public subscript(key: String) -> Any? {
        get {return property(key)}
        set {setProperty(key, newValue)}
    }

    init(_ impl: CBLProperties) {
        _impl = impl
    }

    let _impl: CBLProperties
    
    func convertValue(_ value: Any?, isGetter: Bool) -> Any? {
        switch value {
        case let subdoc as Subdocument:
            return isGetter ? subdoc : subdoc._subdocimpl
        case let implSubdoc as CBLSubdocument:
            if isGetter {
                if let subdoc = implSubdoc.swiftSubdocument {
                    return subdoc
                }
                return Subdocument(implSubdoc)
            }
            return implSubdoc
        case let array as [Any]:
            var result: [Any] = [];
            for v in array {
                result.append(convertValue(v, isGetter: isGetter)!)
            }
            return result
        case let dict as [String: Any]:
            var result: [String: Any] = [:]
            for (k, v) in dict {
                result[k] = convertValue(v, isGetter: isGetter)!
            }
            return result
        default:
            return value
        }
    }
}


public typealias Blob = CBLBlob
