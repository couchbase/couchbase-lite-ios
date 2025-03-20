//
//  QueryDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 12/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import CouchbaseLiteSwift_Private

internal struct QueryResultDecoder: Decoder {
    let queryResult: Result
    
    var codingPath: [any CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(QueryResultDecodingContainer(queryResult: queryResult))
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
    let unnamedDocument: DictionaryObject?
    
    init(queryResult: Result) {
        self.queryResult = queryResult
        // The actual document may be in an unnamed nested dictionary (key '_')
        self.unnamedDocument = queryResult.dictionary(forKey: "_")
    }

    var codingPath: [any CodingKey] = []
    
    var allKeys: [Key] { queryResult.keys.compactMap { Key(stringValue: $0) } }
    
    func contains(_ key: Key) -> Bool {
        queryResult.contains(key: key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = queryResult.value(forKey: key.stringValue) ?? unnamedDocument?.value(forKey: key.stringValue) {
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
                // The actual document may be in an unnamed nested dictionary (key '_')
                ?? unnamedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T(from: valueDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let nestedValue = queryResult.value(forKey: key.stringValue)
                // The actual document may be in an unnamed nested dictionary (key '_')
                ?? unnamedDocument?.value(forKey: key.stringValue) else {
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
                // The actual document may be in an unnamed nested dictionary (key '_')
                ?? unnamedDocument?.value(forKey: key.stringValue) else {
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
                // The actual document may be in an unnamed nested dictionary (key '_')
                ?? unnamedDocument?.value(forKey: "super") else {
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
                // The actual document may be in an unnamed nested dictionary (key '_')
                ?? unnamedDocument?.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLErrorInvalidQuery, description: "Query is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.invalidQuery, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
}
