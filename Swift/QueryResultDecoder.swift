//
//  QueryDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 12/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

internal struct QueryResultDecoder: Decoder {
    let queryResult: Result
    
    var codingPath: [any CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(QueryResultDecodingContainer(queryResult: queryResult))
    }
    
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.requiresKeyedContainer
    }
    
    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.requiresKeyedContainer
    }
}

private struct QueryResultDecodingContainer<Key: CodingKey> : KeyedDecodingContainerProtocol {
    let queryResult: Result
    
    var codingPath: [any CodingKey] = []
    
    var allKeys: [Key] { queryResult.keys.compactMap { Key(stringValue: $0) } }
    
    func contains(_ key: Key) -> Bool {
        queryResult.contains(key: key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = queryResult.value(forKey: key.stringValue) {
            if value is NSNull {
                return true
            } else {
                return false
            }
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No such key '\(key.stringValue)'"))
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        guard let value = queryResult.value(forKey: key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Key not found"))
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T(from: valueDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let nested = queryResult.dictionary(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary for key '\(key.stringValue)'"))
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nested = queryResult.array(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No array for key '\(key.stringValue)'"))
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .array(nested))
        return FleeceArrayDecodingContainer(decoder: nestedDecoder, array: nested)
    }
    
    func superDecoder() throws -> any Decoder {
        guard let nested = queryResult.dictionary(forKey: "super") else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value for key 'super'"))
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
    
    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nested = queryResult.dictionary(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value for key '\(key.stringValue)'"))
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
}
