//
//  FleeceDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 07/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

internal class FleeceDecoder: Decoder {
    let fleeceValue: FleeceValue
    
    init(fleeceValue: FleeceValue) {
        self.fleeceValue = fleeceValue
    }
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey: Any] = [:]
    
    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        switch fleeceValue {
        case .dictionary(let dictionaryObject):
            KeyedDecodingContainer(FleeceDictDecodingContainer(decoder: self, dict: dictionaryObject))
        default:
            throw DecodingError.typeMismatch([String: Any].self, .init(codingPath: codingPath, debugDescription: "Value \(fleeceValue) is not a keyed container"))
        }
    }
    
    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        switch fleeceValue {
        case .array(let arrayObject):
            FleeceArrayDecodingContainer(decoder: self, array: arrayObject)
        default:
            throw DecodingError.typeMismatch([Any].self, .init(codingPath: codingPath, debugDescription: "Value \(fleeceValue) is not an unkeyed container"))
        }
    }
    
    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        switch fleeceValue {
        case .array:
            throw DecodingError.typeMismatch(Any.self, .init(codingPath: codingPath, debugDescription: "Value \(fleeceValue) cannot be decoded as a single value"))
        case .dictionary:
            throw DecodingError.typeMismatch(Any.self, .init(codingPath: codingPath, debugDescription: "Value \(fleeceValue) cannot be decoded as a single value"))
        default:
            SingleValueContainer(decoder: self)
        }
    }
}

internal struct FleeceDictDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: FleeceDecoder
    let dict: DictionaryObject
    
    var codingPath: [CodingKey] = []

    func contains(_ key: Key) -> Bool {
        dict.contains(key: key.stringValue)
    }
    
    var allKeys: [Key] {
        dict.keys.compactMap { Key(stringValue: $0) }
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = dict.value(forKey: key.stringValue) {
            if value is NSNull {
                return true
            } else {
                return false
            }
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Key not found"))
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        guard let value = dict.value(forKey: key.stringValue) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Key not found"))
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T(from: valueDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let nested = dict.dictionary(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary for key '\(key.stringValue)'"))
        }
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: decoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nested = dict.array(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No array for key '\(key.stringValue)'"))
        }
        return FleeceArrayDecodingContainer(decoder: decoder, array: nested)
    }
    
    func superDecoder() throws -> any Decoder {
        guard let nested = dict.dictionary(forKey: "super") else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary for key 'super'"))
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nested = dict.dictionary(forKey: key.stringValue) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value for key '\(key.stringValue)'"))
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
}

internal struct FleeceArrayDecodingContainer: UnkeyedDecodingContainer {
    let decoder: FleeceDecoder
    let array: ArrayProtocol
    
    var codingPath: [any CodingKey] = []
    
    var count: Int? { return array.count }
    
    var isAtEnd: Bool { return currentIndex == array.count }
    
    var currentIndex: Int = 0
    
    mutating func decodeNil() throws -> Bool {
        if let value = array.value(at: currentIndex) {
            if value is NSNull {
                currentIndex += 1
                return true
            } else {
                return false
            }
        }
        throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value at index \(currentIndex)"))
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard let value = array.value(at: currentIndex) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value at index \(currentIndex)"))
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        
        let val = try T(from: valueDecoder)
        currentIndex += 1
        return val
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let nested = array.dictionary(at: currentIndex) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary at index \(currentIndex)"))
        }
        currentIndex += 1
        return KeyedDecodingContainer(FleeceDictDecodingContainer(decoder: decoder, dict: nested))
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let nested = array.array(at: currentIndex) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No array at index \(currentIndex)"))
        }
        currentIndex += 1
        return FleeceArrayDecodingContainer(decoder: decoder, array: nested)
    }
    
    mutating func superDecoder() throws -> any Decoder {
        guard let nested = array.dictionary(at: currentIndex) else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No dictionary at index \(currentIndex)"))
        }
        currentIndex += 1
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }
}

private struct SingleValueContainer: SingleValueDecodingContainer {
    let decoder: FleeceDecoder
    
    var codingPath: [any CodingKey] { return decoder.codingPath }
    
    func decodeNil() -> Bool {
        switch decoder.fleeceValue {
        case .null:
            true
        default:
            false
        }
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        switch decoder.fleeceValue {
        case .bool(let bool):
            bool
        default:
            throw DecodingError.typeMismatch(Bool.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode Bool but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        switch decoder.fleeceValue {
        case .int(let int):
            int
        default:
            throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode Int but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        switch decoder.fleeceValue {
        case .uint(let uint):
            uint
        default:
            throw DecodingError.typeMismatch(UInt.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode UInt but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        switch decoder.fleeceValue {
        case .float(let float):
            float
        default:
            throw DecodingError.typeMismatch(Float.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode Float but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        switch decoder.fleeceValue {
        case .double(let double):
            double
        default:
            throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode Double but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        switch decoder.fleeceValue {
        case .string(let string):
            string
        default:
            throw DecodingError.typeMismatch(String.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode String but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: Data.Type) throws -> Data {
        switch decoder.fleeceValue {
        case .data(let data):
            data
        default:
            throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode Data but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode(_ type: Blob.Type) throws -> Blob {
        switch decoder.fleeceValue {
        case .blob(let blob):
            blob
        default:
            throw DecodingError.typeMismatch(Blob.self, .init(codingPath: codingPath, debugDescription: "Expected to decode Blob but found \(String(describing: decoder.fleeceValue))"))
        }
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        switch type {
        case is Bool.Type:
            return try decode(Bool.self) as! T
        case is Int.Type:
            return try decode(Int.self) as! T
        case is UInt.Type:
            return try decode(UInt.self) as! T
        case is Float.Type:
            return try decode(Float.self) as! T
        case is Double.Type:
            return try decode(Double.self) as! T
        case is String.Type:
            return try decode(String.self) as! T
        case is Data.Type:
            return try decode(Data.self) as! T
        case is Blob.Type:
            return try decode(Blob.self) as! T
        default:
            throw DecodingError.typeMismatch(T.self, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected to decode \(T.self) but found \(String(describing: decoder.fleeceValue))"))
        }
    }
}

enum FleeceValue {
    case null
    case bool(Bool)
    case int(Int)
    case uint(UInt)
    case float(Float)
    case double(Double)
    case string(String)
    case data(Data)
    case blob(Blob)
    case array(ArrayObject)
    case dictionary(DictionaryObject)
    
    private init?(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(int)
        case let uint as UInt:
            self = .uint(uint)
        case let float as Float:
            self = .float(float)
        case let double as Double:
            self = .double(double)
        case let string as String:
            self = .string(string)
        case let data as Data:
            self = .data(data)
        case let blob as Blob:
            self = .blob(blob)
        case let array as ArrayObject:
            self = .array(array)
        case let dictionary as DictionaryObject:
            self = .dictionary(dictionary)
        default:
            return nil
        }
    }
    
    init?<T>(_ value: Any, as type: T.Type) {
        // Early skip for types which are stored as Array or Dict (such as enum or struct)
        if let array = value as? ArrayObject {
            self = .array(array)
            return
        } else if let dictionary = value as? DictionaryObject {
            self = .dictionary(dictionary)
            return
        }
        switch type {
        case is NSNull.Type:
            if value is NSNull { self = .null } else { return nil }
        case is Bool.Type:
            if let v = value as? Bool { self = .bool(v) } else { return nil }
        case is Int.Type:
            if let v = value as? Int { self = .int(v) } else { return nil }
        case is UInt.Type:
            if let v = value as? UInt { self = .uint(v) } else { return nil }
        case is Float.Type:
            if let v = value as? Float { self = .float(v) } else { return nil }
        case is Double.Type:
            if let v = value as? Double { self = .double(v) } else { return nil }
        case is String.Type:
            if let v = value as? String { self = .string(v) } else { return nil }
        case is Data.Type:
            if let v = value as? Data { self = .data(v) } else { return nil }
        case is Blob.Type:
            if value is Blob { self = .blob(value as! Blob) } else { return nil }
        case is Array<any Decodable>.Type:
            if let v = value as? ArrayObject { self = .array(v) } else { return nil }
        case is Dictionary<String, any Decodable>.Type:
            if let v = value as? DictionaryObject { self = .dictionary(v) } else { return nil }
        default:
            self.init(value)
        }
    }
}
