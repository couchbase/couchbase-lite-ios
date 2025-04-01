//
//  DocumentEncoder.swift
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

import Foundation
import CouchbaseLiteSwift_Private

internal class DocumentEncoder: Encoder {
    fileprivate var _encoder: FleeceEncoder
    private var _document: MutableDocument
    
    init(db: Database, document: MutableDocument) throws {
        _encoder = try FleeceEncoder(db: db)
        _document = document
    }
    
    public var codingPath: [any CodingKey] { return _encoder.codingPath }
    
    public var userInfo: [CodingUserInfoKey: Any] { return [:] }
    
    public func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        return KeyedEncodingContainer(try! DocumentEncodingContainer(encoder: self))
    }
    
    public func unkeyedContainer() -> any UnkeyedEncodingContainer {
        return ImpossibleUnkeyedContainer(encoder: self)
    }
    
    public func singleValueContainer() -> any SingleValueEncodingContainer {
        return FleeceSingleValueEncodingContainer(encoder: _encoder)
    }
    
    /// Finish encoding and write the resulting dict into self.document
    func finish() throws {
        try _encoder._encoder.finish(into: _document.impl)
    }
}

// This class mostly just delegates to FleeceEncoder, but also has an important override for encoding DocumentId
private class DocumentEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var encoder: DocumentEncoder
    var codingPath: [CodingKey] = []
    
    init(encoder: DocumentEncoder) throws {
        self.encoder = encoder
        try self.encoder._encoder.beginDict()
    }
    
    deinit {
        try! self.encoder._encoder.endDict()
    }
    
    func encodeNil(forKey key: Key) throws {
        try encoder._encoder.writeKey(key)
        try encoder._encoder.writeNil()
        codingPath.append(key)
    }
    
    // Override for DocumentId to skip encoding id, so it can set encoder.document
    func encode(_ value: DocumentID, forKey key: Key) throws {
        try value.encode(to: encoder)
    }

    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        if value is DocumentID {
            try encode(value as! DocumentID, forKey: key)
            return
        }
        try encoder._encoder.writeKey(key)
        try encoder._encoder.writeValue(value)
        codingPath.append(key)
    }
    
    // Nested containers use FleeceEncoder, because they don't need the override for DocumentId
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        try! encoder._encoder.writeKey(key)
        let container = try! DictEncodingContainer<NestedKey>(encoder: encoder._encoder)
        codingPath.append(key)
        return KeyedEncodingContainer(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        try! encoder._encoder.writeKey(key)
        let container = try! ArrayEncodingContainer(encoder: encoder._encoder)
        codingPath.append(key)
        return container
    }
    
    func superEncoder() -> any Encoder {
        try! encoder._encoder.writeKey("super")
        return encoder._encoder
    }
    
    func superEncoder(forKey key: Key) -> any Encoder {
        try! encoder._encoder.writeKey(key)
        return encoder._encoder
    }
}

// MARK: - Impossible State Containers

private struct ImpossibleUnkeyedContainer: UnkeyedEncodingContainer {
    let encoder: DocumentEncoder
    
    var codingPath: [any CodingKey] { return [] }
    
    var count: Int { return 0 }
    
    func encodeNil() throws {
        throw CBLError.create(CBLError.encodingError, description: "Document encoding requires a keyed container")
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return KeyedEncodingContainer(ImpossibleKeyedContainer<NestedKey>(encoder: encoder))
    }
    
    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        return self
    }
    
    func superEncoder() -> any Encoder {
        return encoder
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        throw CBLError.create(CBLError.encodingError, description: "Document encoding requires a keyed container")
    }
}

private struct ImpossibleKeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: DocumentEncoder
    
    var codingPath: [any CodingKey] { return [] }
    
    func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        throw CBLError.create(CBLError.encodingError, description: "Document encoding requires a keyed container")
    }
    
    func encodeNil(forKey key: Key) throws {
        throw CBLError.create(CBLError.encodingError, description: "Document encoding requires a keyed container")
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return KeyedEncodingContainer(ImpossibleKeyedContainer<NestedKey>(encoder: encoder))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        return ImpossibleUnkeyedContainer(encoder: encoder)
    }
    
    func superEncoder() -> any Encoder {
        return encoder
    }
    
    func superEncoder(forKey key: Key) -> any Encoder {
        return encoder
    }
}
