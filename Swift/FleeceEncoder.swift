//
//  FleeceEncoder.swift
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

internal class FleeceEncoder : Encoder {
    internal let _encoder: CBLEncoder
    private let _context: CBLEncoderContext
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] { return [:] }

    init(db: Database) throws {
        _encoder = try CBLEncoder(db: db.impl)
        _context = CBLEncoderContext(db: db.impl)
        _encoder.setExtraInfo(_context)
    }
    
    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return KeyedEncodingContainer(try! DictEncodingContainer(encoder: self))
    }
    
    public func unkeyedContainer() -> any UnkeyedEncodingContainer {
        return try! ArrayEncodingContainer(encoder: self)
    }
    
    public func singleValueContainer() -> any SingleValueEncodingContainer {
        return FleeceSingleValueEncodingContainer(encoder: self)
    }

    func writeKey<Key: CodingKey>(_ key: Key) throws {
        return try writeKey(key.stringValue)
    }
    
    func writeKey(_ key: String) throws {
        if !_encoder.writeKey(key) {
            let errorMsg = _encoder.getError() ?? "Failed to write key"
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
        }
    }
    
    func writeValue<T>(_ value: T) throws where T: Encodable {
        switch value {
        case is Bool:
            try _writeNSObject(NSNumber(booleanLiteral: value as! Bool))
        case is Int:
            try _writeNSObject(NSNumber(value: value as! Int))
        case is UInt:
            try _writeNSObject(value as! UInt as NSNumber)
        case is Float:
            try _writeNSObject(value as! Float as NSNumber)
        case is Double:
            try _writeNSObject(value as! Double as NSNumber)
        case is String:
            try _writeNSObject(value as! String as NSString)
        case is Data:
            throw CBLError.create(CBLError.encodingError, description: "Cannot encode raw Data, use Blob instead")
        case is Array<any Encodable>:
            let array = value as! Array<any Encodable>
            try beginArray(reserve: array.count)
            for element in array {
                try writeValue(element)
            }
            try endArray()
        case is Dictionary<String, any Encodable>:
            let dict = value as! Dictionary<String, any Encodable>
            try beginDict(reserve: dict.count)
            for (key, value) in dict {
                try writeKey(key)
                try writeValue(value)
            }
            try endDict()
        case is Blob:
            try _writeNSObject((value as! Blob).impl)
        case is Date:
            let formatter = ISO8601DateFormatter()
            let string = formatter.string(from: value as! Date)
            try _writeNSObject(string as NSString)
        case is NSObject:
            try _writeNSObject(value as! NSObject)
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
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
        }
    }
    
    func beginDict(reserve: Int = 10) throws {
        if !_encoder.beginDict(UInt(reserve)) {
            let errorMsg = _encoder.getError() ?? "Failed to begin dictionary"
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
        }
    }
    
    func endArray() throws {
        if !_encoder.endArray() {
            let errorMsg = _encoder.getError() ?? "Failed to end array"
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
        }
    }
    
    func endDict() throws {
        if !_encoder.endDict() {
            let errorMsg = _encoder.getError() ?? "Failed to end dictionary"
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
        }
    }
    
    private func _writeNSObject(_ value: NSObject) throws {
        if !_encoder.write(value) {
            let errorMsg = _encoder.getError() ?? "Failed to write object \(String(describing: value))"
            throw CBLError.create(CBLError.encodingError, description: errorMsg)
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
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        try encoder.writeKey(key)
        try encoder.writeValue(value)
    }
    
    func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T : Encodable {
        if value != nil {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        try! encoder.writeKey(key)
        let container = try! DictEncodingContainer<NestedKey>(encoder: encoder)
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        try! encoder.writeKey(key)
        let container = try! ArrayEncodingContainer(encoder: encoder)
        return container
    }
    
    func superEncoder() -> any Encoder {
        try! encoder.writeKey("super")
        return encoder
    }
    
    func superEncoder(forKey key: Key) -> any Encoder {
        try! encoder.writeKey(key)
        return encoder
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
