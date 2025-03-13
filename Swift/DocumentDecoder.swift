//
//  FleeceDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

internal struct DocumentDecoder: Decoder {
    internal let document: MutableDocument
    
    internal init(document: MutableDocument) {
        self.document = document
    }
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        KeyedDecodingContainer(DocumentDecodingContainer(decoder: self))
    }
    
    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        ImpossibleUnkeyedDecodingContainer()
    }
    
    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        ImpossibleSingleValueDecodingContainer()
    }
}

private struct DocumentDecodingContainer<Key: CodingKey> : KeyedDecodingContainerProtocol {
    let decoder: DocumentDecoder
    
    var codingPath: [any CodingKey] { return decoder.codingPath }
    var allKeys: [Key] { return decoder.document.keys.compactMap { Key(stringValue: $0) }}
    
    func contains(_ key: Key) -> Bool {
        decoder.document.contains(key: key.stringValue)
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = decoder.document.value(forKey: key.stringValue) {
            if value is NSNull {
                return true
            } else {
                return false
            }
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value for key '\(key.stringValue)'"))
    }
    
    // Specialisation for DocumentId to take self.document instead of decoding id
    func decode(_ type: DocumentId.Type, forKey key: Key) throws -> DocumentId {
        return try DocumentId(from: decoder)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        if type is DocumentId.Type {
            return try decode(DocumentId.self, forKey: key) as! T
        }
        guard let value = decoder.document.value(forKey: key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No value for key '\(key.stringValue)'"))
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T.init(from: valueDecoder)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let nested = decoder.document.dictionary(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary for key '\(key.stringValue)'"))
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nested = decoder.document.array(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No array for key '\(key.stringValue)'"))
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .array(nested))
        return FleeceArrayDecodingContainer(decoder: nestedDecoder, array: nested)
    }
    

    func superDecoder() throws -> any Decoder {
        guard let nested = decoder.document.dictionary(forKey: "super") else {
            throw DecodingError.keyNotFound(SuperKey.key, .init(codingPath: codingPath, debugDescription: "No dictionary for key 'super'"))
        }
        return FleeceDecoder(fleeceValue: .dictionary(nested))
    }
    
    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nested = decoder.document.dictionary(forKey: key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No dictionary for key '\(key.stringValue)'"))
        }
        return FleeceDecoder(fleeceValue: .dictionary(nested))
    }
}

private struct ImpossibleUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    var codingPath: [any CodingKey] { return [] }
    
    var count: Int? { return 0 }
    
    var isAtEnd: Bool { return true }
    
    var currentIndex: Int { return 0 }
    
    mutating func decodeNil() throws -> Bool {
        throw DecodingError.requiresKeyedContainer
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw DecodingError.requiresKeyedContainer
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.requiresKeyedContainer
    }
    
    mutating func superDecoder() throws -> any Decoder {
        throw DecodingError.requiresKeyedContainer
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        throw DecodingError.requiresKeyedContainer
    }
}

private struct ImpossibleKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [any CodingKey] { return [] }
    
    var allKeys: [Key] { return [] }
    
    func contains(_ key: Key) -> Bool {
        false
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        throw DecodingError.requiresKeyedContainer
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw DecodingError.requiresKeyedContainer
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw DecodingError.requiresKeyedContainer
    }
    
    func superDecoder() throws -> any Decoder {
        throw DecodingError.requiresKeyedContainer
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        throw DecodingError.requiresKeyedContainer
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        throw DecodingError.requiresKeyedContainer
    }
}

private struct ImpossibleSingleValueDecodingContainer : SingleValueDecodingContainer {
    var codingPath: [any CodingKey] { return [] }
    
    func decodeNil() -> Bool {
        false
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        throw DecodingError.requiresKeyedContainer
    }
}

enum DecodingError : Swift.Error {
    case requiresKeyedContainer
    case requiresUnkeyedContainer
    case keyNotFound(any CodingKey, DecodingError.Context)
    case valueNotFound(DecodingError.Context)
    case typeMismatch(Any.Type, DecodingError.Context)
}

extension DecodingError {
    struct Context {
        let codingPath: [any CodingKey]
        let debugDescription: String
    }
}

enum SuperKey: String, CodingKey {
    case key = "super"
}
