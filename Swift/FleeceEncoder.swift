//
//  FleeceEncoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 05/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import CouchbaseLiteSwift_Private

internal class FleeceEncoder : Encoder {
    internal let _encoder: CBLEncoder
    private let _context: CBLEncoderContext
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] = [:]

    init(db: Database) throws {
        _encoder = try CBLEncoder(db: db.impl)
        _context = CBLEncoderContext(db: db.impl)
        _encoder.setExtraInfo(_context)
    }
    
    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        KeyedEncodingContainer(try! DictEncodingContainer(encoder: self))
    }
    
    public func unkeyedContainer() -> any UnkeyedEncodingContainer {
        try! ArrayEncodingContainer(encoder: self)
    }
    
    public func singleValueContainer() -> any SingleValueEncodingContainer {
        FleeceSingleValueEncodingContainer(encoder: self)
    }

    func writeKey<Key: CodingKey>(_ key: Key) throws {
        try writeKey(key.stringValue)
    }
    
    func writeKey(_ key: String) throws {
        if !_encoder.writeKey(key) {
            let errorMsg = _encoder.getError() ?? "Failed to write key"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
    
    func writeValue<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let bool as Bool:
            try _writeNSObject(NSNumber(booleanLiteral: bool))
        case let int as Int:
            try _writeNSObject(int as NSNumber)
        case let uint as UInt:
            try _writeNSObject(uint as NSNumber)
        case let float as Float:
            try _writeNSObject(float as NSNumber)
        case let double as Double:
            try _writeNSObject(double as NSNumber)
        case let string as String:
            try _writeNSObject(string as NSString)
        case let data as Data:
            try _writeNSObject(data as NSData)
        case let array as Array<any Encodable>:
            try beginArray(reserve: array.count)
            for element in array {
                try writeValue(element)
            }
            try endArray()
        case let dict as Dictionary<String, any Encodable>:
            try beginDict(reserve: dict.count)
            for (key, value) in dict {
                try writeKey(key)
                try writeValue(value)
            }
            try endDict()
        case let blob as Blob:
            try _writeNSObject(blob.impl)
        case let object as NSObject:
            try _writeNSObject(object)
        default:
            try value.encode(to: self)
        }
    }
    
    func writeNil() throws {
        try _writeNSObject(NSNull())
    }

    func beginArray(reserve: Int = 10) throws {
        if !_encoder.beginArray(UInt(reserve)) {
            let errorMsg = _encoder.getError() ?? "Failed to begin array"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
    
    func beginDict(reserve: Int = 10) throws {
        if !_encoder.beginDict(UInt(reserve)) {
            let errorMsg = _encoder.getError() ?? "Failed to begin dictionary"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
    
    func endArray() throws {
        if !_encoder.endArray() {
            let errorMsg = _encoder.getError() ?? "Failed to end array"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
    
    func endDict() throws {
        if !_encoder.endDict() {
            let errorMsg = _encoder.getError() ?? "Failed to end dictionary"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
    
    private func _writeNSObject(_ value: NSObject) throws {
        if !_encoder.write(value) {
            let errorMsg = _encoder.getError() ?? "Failed to write NSObject"
            throw EncoderError.invalidOperation(EncoderError.Context(codingPath: [], debugDescription: errorMsg))
        }
    }
}


internal class ArrayEncodingContainer: UnkeyedEncodingContainer {
    var encoder: FleeceEncoder
    var codingPath: [CodingKey] { return [] }
    var count: Int = 0
    
    init(encoder: FleeceEncoder) throws {
        self.encoder = encoder
        try encoder.beginArray()
    }
    
    deinit {
        try! self.encoder.endArray()
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        count += 1
        return KeyedEncodingContainer(try! DictEncodingContainer(encoder: encoder))
    }
    
    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        count += 1
        return try! ArrayEncodingContainer(encoder: encoder)
    }
    
    func superEncoder() -> any Encoder {
        return encoder
    }
    
    func encodeNil() throws {
        count += 1
        try encoder.writeNil()
    }
    
    func encode<T>(_ value: T) throws where T: Encodable {
        count += 1
        try encoder.writeValue(value)
    }
}

internal class DictEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var encoder: FleeceEncoder
    var codingPath: [CodingKey] = []
    
    init(encoder: FleeceEncoder) throws {
        self.encoder = encoder
        try self.encoder.beginDict()
    }
    
    deinit {
        try! self.encoder.endDict()
    }
    
    func encodeNil(forKey key: Key) throws {
        try encoder.writeKey(key)
        try encoder.writeNil()
        codingPath.append(key)
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        try encoder.writeKey(key)
        try encoder.writeValue(value)
        codingPath.append(key)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        try! encoder.writeKey(key)
        let container = try! DictEncodingContainer<NestedKey>(encoder: encoder)
        codingPath.append(key)
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        try! encoder.writeKey(key)
        let container = try! ArrayEncodingContainer(encoder: encoder)
        codingPath.append(key)
        return container
    }
    
    func superEncoder() -> any Encoder {
        encoder
    }
    
    func superEncoder(forKey key: Key) -> any Encoder {
        encoder
    }
}

internal struct FleeceSingleValueEncodingContainer: SingleValueEncodingContainer {
    var codingPath: [any CodingKey] { return [] }
    var encoder: FleeceEncoder
    
    func encodeNil() throws {
        try encoder.writeNil()
    }
    
    func encode<T>(_ value: T) throws where T: Encodable {
        try encoder.writeValue(value)
    }
}
