//
//  QueryResultDecoder.swift
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

import CouchbaseLiteSwift_Private

internal struct QueryResultDecoder: Decoder {
    let queryResult: Result
    let dataKey: String?
    
    init(queryResult: Result, dataKey: String? = nil) {
        self.queryResult = queryResult
        self.dataKey = dataKey
    }
    
    var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] { [:] }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(QueryResultDecodingContainer(queryResult: queryResult, dataKey: dataKey))
    }
    
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw CBLError.create(CBLError.decodingError, description: "Result decoding requires a keyed container")
    }
    
    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw CBLError.create(CBLError.decodingError, description: "Result decoding requires a keyed container")
    }
}

private struct QueryResultDecodingContainer<Key: CodingKey> : KeyedDecodingContainerProtocol {
    let queryResult: Result
    let nestedDocument: DictionaryObject?
    
    init(queryResult: Result, dataKey: String? = nil) {
        self.queryResult = queryResult
        // The actual document may be in a nested dictionary, if `SELECT id, *` was used
        self.nestedDocument = dataKey != nil ? queryResult.dictionary(forKey: dataKey!) : nil
    }

    var codingPath: [any CodingKey] = []
    
    var allKeys: [Key] { queryResult.keys.compactMap { Key(stringValue: $0) } }
    
    func contains(_ key: Key) -> Bool {
        queryResult.contains(key: key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = queryResult.value(forKey: key.stringValue) ?? nestedDocument?.value(forKey: key.stringValue) {
            if value is NSNull {
                return true
            } else {
                return false
            }
        }
        throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        guard let value = queryResult.value(forKey: key.stringValue)
                ?? nestedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            throw CBLError.create(CBLError.decodingError, description: "Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        // Override to avoid default Date decode implementation
        if type is Date.Type {
            let container = try valueDecoder.singleValueContainer()
            return try container.decode(type)
        }
        return try T(from: valueDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let nestedValue = queryResult.value(forKey: key.stringValue)
                ?? nestedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.invalidQuery, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nestedValue = queryResult.value(forKey: key.stringValue)
                ?? nestedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? ArrayObject else {
            throw CBLError.create(CBLError.invalidQuery, description: "Type mismatch for key '\(key.stringValue)': expected array, found \(String(describing: nestedValue))")
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .array(nested))
        return FleeceArrayDecodingContainer(decoder: nestedDecoder, array: nested)
    }
    
    func superDecoder() throws -> any Decoder {
        guard let nestedValue = queryResult.value(forKey: "super")
                ?? nestedDocument?.value(forKey: "super") else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field 'super'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.invalidQuery, description: "Type mismatch for key 'super': expected dictionary, found \(String(describing: nestedValue))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
    
    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nestedValue = queryResult.value(forKey: key.stringValue)
                ?? nestedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.invalidQuery, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
}
