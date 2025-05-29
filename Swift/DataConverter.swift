//
//  DataConverter.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import CouchbaseLiteSwift_Private

/* internal */ class DataConverter {
    
    static func unwrap<T: AnyObject>(_ swiftObject: Any?) -> T? {
        if let holder = swiftObject as? WeakHolder,
           let value = holder.object as? T {
            return value
        }
        return nil
    }
    
    static func convertGETValue(_ value: Any?) -> Any? {
        switch value {
        case let impl as CBLMutableDictionary:
            if let dict: MutableDictionaryObject = unwrap(impl.swiftObject) {
                return dict
            }
            return MutableDictionaryObject(impl)
        case let impl as CBLMutableArray:
            if let array: MutableArrayObject = unwrap(impl.swiftObject) {
                return array
            }
            return MutableArrayObject(impl)
        case let impl as CBLDictionary:
            if let dict: DictionaryObject = unwrap(impl.swiftObject) {
                return dict
            }
            return DictionaryObject(impl)
        case let impl as CBLNewDictionary:
            if let dict: DictionaryObject = unwrap(impl.swiftObject) {
                return dict
            }
            return DictionaryObject(impl)
        case let impl as CBLArray:
            if let array: ArrayObject = unwrap(impl.swiftObject) {
                return array
            }
            return ArrayObject(impl)
        case let impl as CBLBlob:
            if let blob: Blob = unwrap(impl.swiftObject) {
                return blob
            }
            return Blob(impl)
        default:
            return value
        }
        
    }
    
    static func convertSETValue(_ value: Any?) -> Any? {
        switch value {
        case let dict as DictionaryObject:
            return dict.impl
        case let array as ArrayObject:
            return array.impl
        case let blob as Blob:
            return blob.impl
        case let dict as Dictionary<String, Any>:
            return convertSETDictionary(dict)
        case let array as Array<Any>:
            return convertSETArray(array)
        default:
            return value
        }
    }
    
    static func convertSETDictionary(_ dictionary: [String: Any]?) -> [String: Any] {
        guard let dict = dictionary else {
            return [:]
        }
        
        var result: [String: Any] = [:]
        for (key, value) in dict {
            result[key] = DataConverter.convertSETValue(value)
        }
        return result
    }
    
    static func convertSETArray(_ array: [Any]?) -> [Any] {
        guard let a = array else {
            return []
        }
        
        var result: [Any] = [];
        for v in a {
            result.append(DataConverter.convertSETValue(v)!)
        }
        return result
    }
    
    static func toPlainObject(_ value: Any?) -> Any? {
        switch value {
        case let v as DictionaryObject:
            return v.toDictionary()
        case let v as ArrayObject:
            return v.toArray()
        default:
            return value
        }
    }
}
