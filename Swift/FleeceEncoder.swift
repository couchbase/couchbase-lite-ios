//
//  FleeceEncoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 10/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import Foundation
import CouchbaseLiteSwift_Private

public class FleeceEncoder: Encoder {
    fileprivate var _encoder: CBLEncoder
    
    init() {
        _encoder = CBLEncoder()
    }
    
    init(withDB db: CBLDatabase) {
        _encoder = CBLEncoder(db: db)
    }
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey: Any] = [:]
    
    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        return KeyedEncodingContainer(try! KeyedContainer<Key>(encoder: self))
    }
    
    public func unkeyedContainer() -> any UnkeyedEncodingContainer {
        return try! UnkeyedContainer(encoder: self)
    }
    
    public func singleValueContainer() -> any SingleValueEncodingContainer {
        return SingleValueContainer(encoder: self)
    }

    func beginDict() throws {
        if !_encoder.beginDict(10) {
            let errorMsg = _encoder.getError() ?? "Failed to open dictionary"
            throw Error.invalidOperation(Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func endDict() throws {
        if !_encoder.endDict() {
            let errorMsg = _encoder.getError() ?? "Failed to end dictionary"
            throw Error.invalidOperation(Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func beginArray() throws {
        if !_encoder.beginArray(10) {
            let errorMsg = _encoder.getError() ?? "Failed to begin array"
            throw Error.invalidOperation(Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func endArray() throws {
        if !_encoder.endArray() {
            let errorMsg = _encoder.getError() ?? "Failed to end array"
            throw Error.invalidOperation(Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func writeKey<Key>(_ key: Key) throws where Key: CodingKey {
        codingPath.append(key)
        if !_encoder.writeKey(key.stringValue) {
            let errorMsg = _encoder.getError() ?? "Failed to encode key"
            throw Error.invalidKey(key, Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func writeValue<T>(_ value: T) throws where T: Encodable {
        if let v = value as? FleeceEncodable {
            try writeValue(v)
        } else {
            throw Error.typeNotConformingToFleeceEncodable(T.self)
        }
    }
    
    func writeValue<T>(_ value: T) throws where T: FleeceEncodable {
        if !_encoder.write(value.asNSObject()) {
            let errorMsg = _encoder.getError() ?? "Failed to encode value"
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
    
    func writeNil() throws {
        if !_encoder.write(NSNull()) {
            let errorMsg = _encoder.getError() ?? "Failed to encode nil"
            throw Error.invalidValue(NSNull(), Error.Context(codingPath: codingPath, debugDescription: errorMsg))
        }
    }
}

private enum ContainerType {
    case array
    case dict
}

private class ContainerCloser {
    var encoder: FleeceEncoder
    let type: ContainerType
    
    init(encoder: FleeceEncoder, type: ContainerType) {
        self.encoder = encoder
        self.type = type
    }
    
    deinit {
        if self.type == .array {
            try! self.encoder.endArray()
        } else {
            try! self.encoder.endDict()
        }
    }
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
    var encoder: FleeceEncoder
    var codingPath: [CodingKey]
    var count: Int = 0
    var closer: ContainerCloser
    
    init(encoder: FleeceEncoder) throws {
        self.encoder = encoder
        closer = ContainerCloser(encoder: self.encoder, type: .array)
        codingPath = encoder.codingPath
        try encoder.beginArray()
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        return KeyedEncodingContainer(try! KeyedContainer(encoder: encoder))
    }
    
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        return try! UnkeyedContainer(encoder: encoder)
    }
    
    func superEncoder() -> any Encoder {
        return encoder
    }
    
    func encodeNil() throws {
        try encoder.writeNil()
    }
    
    func encode<T>(_ value: T) throws where T: Encodable {
        try encoder.writeValue(value)
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var encoder: FleeceEncoder
    var codingPath: [CodingKey] = []
    var closer: ContainerCloser
    
    init(encoder: FleeceEncoder) throws {
        self.encoder = encoder
        closer = ContainerCloser(encoder: self.encoder, type: .dict)
        try self.encoder.beginDict()
    }
    
    mutating func encodeNil(forKey key: Key) throws {
        codingPath.append(key)
        try encoder.writeKey(key)
        try encoder.writeNil()
    }

    public mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        codingPath.append(key)
        try encoder.writeKey(key)
        try encoder.writeValue(value)
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        codingPath.append(key)
        try! encoder.writeKey(key)
        
        return KeyedEncodingContainer(try! KeyedContainer<NestedKey>(encoder: encoder))
    }
    
    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        codingPath.append(key)
        try! encoder.writeKey(key)
        
        return try! UnkeyedContainer(encoder: encoder)
    }
    
    mutating func superEncoder() -> any Encoder {
        encoder
    }
    
    mutating func superEncoder(forKey key: Key) -> any Encoder {
        encoder
    }
}

private struct SingleValueContainer : SingleValueEncodingContainer {
    var codingPath: [any CodingKey] = []
    var encoder: FleeceEncoder
    
    init(encoder: FleeceEncoder) {
        self.encoder = encoder
    }
    
    mutating func encodeNil() throws {
        try encoder.writeNil()
    }
    
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        try encoder.writeValue(value)
    }
}

enum Error: Swift.Error {
    case typeNotConformingToFleeceEncodable(Encodable.Type)
    case typeNotConformingToEncodable(Any.Type)
    case invalidKey(CodingKey, Error.Context)
    case invalidValue(Any, Error.Context)
    case invalidOperation(Error.Context)
}

extension Error {
    struct Context {
        let debugDescription: String
        let codingPath: [CodingKey]
        
        init(codingPath: [CodingKey], debugDescription: String) {
            self.codingPath = codingPath
            self.debugDescription = debugDescription
        }
    }
}
