//
//  Properties.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Properties defines a JSON-compatible object, much like a Dictionory but with
 type-safe accessors. It is implemented by classes Document and Subdocument. */
public class Properties {
    /** All of the properties contained in this object. */
    public var properties : [String:Any]? {
        get {return convertProperties(_impl.properties, isGetter: true)}
        set {_impl.properties = convertProperties(newValue, isGetter: false)}
    }

    /** Gets an property's value as an object. Returns types NSNull, Number, String, Array, 
     Dictionary, and Blob, based on the underlying data type; or nil if the property doesn't
     exist. */
    public func property(_ key: String) -> Any? {
        return convertValue(_impl.object(forKey: key), isGetter: true)
    }
    
    /** Sets a property value by key.
     Allowed value types are NSNull, Number, String, Array, Dictionary, Date,
     Subdocument, and Blob. Arrays and Dictionaries must contain only the above types.
     Setting a nil value will remove the property.
     
     Note:
     * A Date object will be converted to an ISO-8601 format string.
     * When setting a subdocument, the subdocument will be set by reference. However,
     if the subdocument has already been set to another key either on the same or different
     document, the value of the subdocument will be copied instead. */
    public func setProperty(_ key: String, _ value: Any?) {
        return _impl.setObject(convertValue(value, isGetter: false), forKey: key)
    }

    /** Tests whether a property exists or not.
     This can be less expensive than calling property(key):, because it does not have to allocate an
     object for the property value. */
    public func contains(_ key: String) -> Bool {
        return _impl.containsObject(forKey: key)
    }
    
    /** Gets a property's value as a boolean.
     Returns YES if the value exists, and is either `true` or a nonzero number. */
    public subscript(key: String) -> Bool {
        get {return _impl.boolean(forKey: key)}
        set {_impl.setBoolean(newValue, forKey: key)}
    }

    /** Gets a property's value as an integer.
     Floating point values will be rounded. The value `true` is returned as 1, `false` as 0.
     Returns 0 if the property doesn't exist or does not have a numeric value. */
    public subscript(key: String) -> Int {
        get {return _impl.integer(forKey: key)}
        set {_impl.setInteger(newValue, forKey: key)}
    }

    /** Gets a property's value as a float.
     Integers will be converted to float. The value `true` is returned as 1.0, `false` as 0.0.
     Returns 0.0 if the property doesn't exist or does not have a numeric value. */
    public subscript(key: String) -> Float {
        get {return _impl.float(forKey: key)}
        set {_impl.setFloat(newValue, forKey: key)}
    }

    /** Gets a property's value as a double.
     Integers will be converted to double. The value `true` is returned as 1.0, `false` as 0.0.
     Returns 0.0 if the property doesn't exist or does not have a numeric value. */
    public subscript(key: String) -> Double {
        get {return _impl.double(forKey: key)}
        set {_impl.setDouble(newValue, forKey: key)}
    }

    /** Gets a property's value as a string.
     Returns nil if the property doesn't exist, or its value is not a string. */
    public subscript(key: String) -> String? {
        get {return _impl.string(forKey: key)}
    }

    /** Gets a property's value as an NSDate.
     JSON does not directly support dates, so the actual property value must be a string, which is
     then parsed according to the ISO-8601 date format (the default used in JSON.)
     Returns nil if the value doesn't exist, is not a string, or is not parseable as a date.
     NOTE: This is not a generic date parser! It only recognizes the ISO-8601 format, with or
     without milliseconds. */
    public subscript(key: String) -> Date? {
        get {return _impl.date(forKey: key)}
    }

    /** Gets a property's value as a blob object.
     Returns nil if the property doesn't exist, or its value is not a blob. */
    public subscript(key: String) -> Blob? {
        get {return _impl.object(forKey: key) as? Blob}
    }
    
    /** Get a property's value as an array object. 
      Returns nil if the property doesn't exist, or its value is not an array. */
    public subscript(key: String) -> [Any]? {
        get {return property(key) as? [Any]}
    }
    
    /** Get a property's value as a Subdocument, which is a mapping object of a Dictionary
     value to provide property type accessors.
     Returns nil if the property doesn't exists, or its value is not a Dictionary. */
    public subscript(key: String) -> Subdocument? {
        get {return property(key) as? Subdocument}
    }
    
    /** Gets an property's value as an object. Returns types NSNull, Number, String, Array,
     Dictionary, and Blob, based on the underlying data type; or nil if the property doesn't
     exist. */
    public subscript(key: String) -> Any? {
        get {return property(key)}
        set {setProperty(key, newValue)}
    }
    
    // MARK: Internal

    init(_ impl: CBLProperties) {
        _impl = impl
    }

    let _impl: CBLProperties
    
    func convertProperties(_ properties: [String: Any]?, isGetter: Bool) -> [String: Any]? {
        if let props = properties {
            var result: [String: Any] = [:]
            for (key, value) in props {
                result[key] = convertValue(value, isGetter: isGetter)
            }
            return result
        }
        return nil
    }
    
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
        default:
            return value
        }
    }
}

public typealias Blob = CBLBlob
