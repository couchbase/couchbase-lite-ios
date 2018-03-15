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


/* internal */ class DataConverter {
    static func convertGETValue(_ value: Any?) -> Any? {
        switch value {
        case let impl as CBLMutableDictionary:
            if let dict = impl.swiftObject {
                return dict
            }
            return MutableDictionaryObject(impl)
        case let impl as CBLMutableArray:
            if let array = impl.swiftObject {
                return array
            }
            return MutableArrayObject(impl)
        case let impl as CBLDictionary:
            if let dict = impl.swiftObject {
                return dict
            }
            return DictionaryObject(impl)
        case let impl as CBLArray:
            if let array = impl.swiftObject {
                return array
            }
            return ArrayObject(impl)
        case let impl as CBLBlob:
            if let blob = impl.swiftObject {
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
            return dict._impl
        case let array as ArrayObject:
            return array._impl
        case let blob as Blob:
            return blob._impl
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

