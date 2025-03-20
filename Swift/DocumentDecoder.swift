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
        throw CBLError.create(CBLError.decodingError, description: "Document decoding requires a keyed container")
    }
    
    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw CBLError.create(CBLError.decodingError, description: "Document decoding requires a keyed container")
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
        throw CBLError.create(CBLError.decodingError, description: "Document is missing field '\(key.stringValue)'")
    }
    
    // Specialisation for DocumentId to take self.document instead of decoding id
    func decode(_ type: DocumentId.Type, forKey key: Key) throws -> DocumentId {
        return try DocumentId(from: decoder)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        // The above override for DocumentId doesn't always work, so we need to double check
        if type is DocumentId.Type {
            return try decode(DocumentId.self, forKey: key) as! T
        }
        guard let value = decoder.document.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Document is missing field '\(key.stringValue)'")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T.init(from: valueDecoder)
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        guard let nestedValue = decoder.document.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Document is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: nestedDecoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nestedValue = decoder.document.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Document is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? ArrayObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected array, found \(String(describing: nestedValue))")
        }
        let nestedDecoder = FleeceDecoder(fleeceValue: .array(nested))
        return FleeceArrayDecodingContainer(decoder: nestedDecoder, array: nested)
    }
    

    func superDecoder() throws -> any Decoder {
        guard let nestedValue = decoder.document.value(forKey: "super") else {
            throw CBLError.create(CBLError.decodingError, description: "Document is missing field 'super'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key 'super': expected dictionary, found \(String(describing: nestedValue))")
        }
        return FleeceDecoder(fleeceValue: .dictionary(nested))
    }
    
    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nestedValue = decoder.document.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Document is missing field '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        return FleeceDecoder(fleeceValue: .dictionary(nested))
    }
}
