//
//  DataConverter.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/* internal */ class DataConverter {
    static func convertGETValue(_ value: Any?) -> Any? {
        switch value {
        case let implDict as CBLMutableDictionary:
            if let dict = implDict.swiftObject {
                return dict
            }
            return MutableDictionaryObject(implDict)
        case let implArray as CBLMutableArray:
            if let array = implArray.swiftObject {
                return array
            }
            return MutableArrayObject(implArray)
        case let implDict as CBLDictionary:
            if let dict = implDict.swiftObject {
                return dict
            }
            return DictionaryObject(implDict)
        case let implArray as CBLArray:
            if let array = implArray.swiftObject {
                return array
            }
            return ArrayObject(implArray)
        default:
            return value
        }
    }
    
    
    static func convertSETValue(_ value: Any?) -> Any? {
        switch value {
        case let dict as MutableDictionaryObject:
            return dict._impl
        case let array as MutableArrayObject:
            return array._impl
        default:
            return value
        }
    }
    
    
    static func convertSETDictionary(_ dictionary: [String: Any]?) -> [String: Any]? {
        guard let dict = dictionary else {
            return nil
        }
        
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = DataConverter.convertSETValue(value)
        }
        return result
    }
    
    
    static func convertSETArray(_ array: [Any]?) -> [Any]? {
        guard let a = array else {
            return nil
        }
        
        var result: [Any] = [];
        for v in a {
            result.append(DataConverter.convertSETValue(v)!)
        }
        return result
    }
}
