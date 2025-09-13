//
//  FleeceDecoder.swift
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

internal class FleeceDecoder: Decoder {
    let fleeceValue: FleeceValue
    
    init(fleeceValue: FleeceValue) {
        self.fleeceValue = fleeceValue
    }
    
    public var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] { return [:] }

    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        switch fleeceValue {
        case .dictionary(let dictionaryObject):
            return KeyedDecodingContainer(FleeceDictDecodingContainer<Key>(decoder: self, dict: dictionaryObject))
        default:
            throw CBLError.create(CBLError.decodingError, description: "Value \(fleeceValue) is not a keyed container")
        }
    }
    
    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        switch fleeceValue {
        case .array(let arrayObject):
            return FleeceArrayDecodingContainer(decoder: self, array: arrayObject)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Value \(fleeceValue) is not an unkeyed container")
        }
    }
    
    public func singleValueContainer() throws -> any SingleValueDecodingContainer {
        switch fleeceValue {
        case .array:
            throw CBLError.create(CBLError.decodingError, description: "Value \(fleeceValue) cannot be decoded as a single value")
        case .dictionary:
            throw CBLError.create(CBLError.decodingError, description: "Value \(fleeceValue) cannot be decoded as a single value")
        default:
            return SingleValueContainer(decoder: self)
        }
    }
}

internal struct FleeceDictDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let decoder: FleeceDecoder
    let dict: DictionaryProtocol
    
    var codingPath: [CodingKey] = []

    func contains(_ key: Key) -> Bool {
        return dict.contains(key: key.stringValue)
    }
    
    var allKeys: [Key] {
        return dict.keys.compactMap { Key(stringValue: $0) }
    }
    
    func decodeNil(forKey key: Key) throws -> Bool {
        if let value = dict.value(forKey: key.stringValue) {
            if value is NSNull {
                return true
            } else {
                return false
            }
        }
        throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        guard let value = dict.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            throw CBLError.create(CBLError.decodingError, description: "Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        return try T(from: valueDecoder)
    }
    
    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let nestedValue = dict.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
        }
        return KeyedDecodingContainer(FleeceDictDecodingContainer<NestedKey>(decoder: decoder, dict: nested))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard let nestedValue = dict.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? ArrayObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected array, found \(String(describing: nestedValue))")
        }
        return FleeceArrayDecodingContainer(decoder: decoder, array: nested)
    }
    
    func superDecoder() throws -> any Decoder {
        guard let nestedValue = dict.value(forKey: "super") else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key 'super'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key 'super': expected dictionary, found \(String(describing: nestedValue))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: .dictionary(nested))
        return valueDecoder
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        guard let nestedValue = dict.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for key '\(key.stringValue)': expected dictionary, found \(String(describing: nestedValue))")
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
        throw CBLError.create(CBLError.decodingError, description: "Array is missing index \(currentIndex)")
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        guard let value = array.value(at: currentIndex) else {
            throw CBLError.create(CBLError.decodingError, description: "Array is missing index \(currentIndex)")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            throw CBLError.create(CBLError.decodingError, description: "Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
        }
        let valueDecoder = FleeceDecoder(fleeceValue: fleeceValue)
        
        let val = try T(from: valueDecoder)
        currentIndex += 1
        return val
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        guard let nestedValue = array.value(at: currentIndex) else {
            throw CBLError.create(CBLError.decodingError, description: "Array is missing index \(currentIndex)")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for index \(currentIndex): expected dictionary, found \(String(describing: nestedValue))")
        }
        currentIndex += 1
        return KeyedDecodingContainer(FleeceDictDecodingContainer(decoder: decoder, dict: nested))
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard let nestedValue = array.value(at: currentIndex) else {
            throw CBLError.create(CBLError.decodingError, description: "Array is missing index \(currentIndex)")
        }
        guard let nested = nestedValue as? ArrayObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for index \(currentIndex): expected array, found \(String(describing: nestedValue))")
        }
        currentIndex += 1
        return FleeceArrayDecodingContainer(decoder: decoder, array: nested)
    }
    
    mutating func superDecoder() throws -> any Decoder {
        guard let nestedValue = array.value(at: currentIndex) else {
            throw CBLError.create(CBLError.decodingError, description: "Array is missing index \(currentIndex)")
        }
        guard let nested = nestedValue as? DictionaryObject else {
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch for index \(currentIndex): expected dictionary, found \(String(describing: nestedValue))")
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
            return true
        default:
            return false
        }
    }
    
    func decode(_ type: Bool.Type) throws -> Bool {
        switch decoder.fleeceValue {
        case .bool(let bool):
            return bool
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Bool but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        switch decoder.fleeceValue {
        case .int(let int):
            return Int(int)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Int but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Int16.Type) throws -> Int16 {
        switch decoder.fleeceValue {
        case .int(let int):
            return Int16(int)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Int16 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Int32.Type) throws -> Int32 {
        switch decoder.fleeceValue {
        case .int(let int):
            return Int32(int)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Int32 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Int64.Type) throws -> Int64 {
        switch decoder.fleeceValue {
        case .int(let int):
            return Int64(int)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Int64 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        switch decoder.fleeceValue {
        case .uint(let uint):
            return UInt(uint)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected UInt but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: UInt16.Type) throws -> UInt16 {
        switch decoder.fleeceValue {
        case .uint(let uint):
            return UInt16(uint)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected UInt16 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: UInt32.Type) throws -> UInt32 {
        switch decoder.fleeceValue {
        case .uint(let uint):
            return UInt32(uint)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected UInt32 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: UInt64.Type) throws -> UInt64 {
        switch decoder.fleeceValue {
        case .uint(let uint):
            return UInt64(uint)
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected UInt64 but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        switch decoder.fleeceValue {
        case .float(let float):
            return float
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Float but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        switch decoder.fleeceValue {
        case .double(let double):
            return double
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Double but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Date.Type) throws -> Date {
        switch decoder.fleeceValue {
        case .string(let string):
            if let date = ISO8601DateFormatter.couchbase.date(from: string) {
                return date
            } else if let date = ISO8601DateFormatter().date(from: string) {
                // CBL-7061. Because of an issue introduced in 3.2.3 which used the default formatter for dates, some customers may have dates in their documents which are
                // encoded using the default formatter (rather than the `.couchbase` formatter).
                // We can remove this extra check once we are sure no customers have default formatter dates in their databases.
                return date
            } else {
                throw CBLError.create(CBLError.decodingError, description: "Failed to parse ISO8601 Date from '\(string)'")
            }
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Date encoded as String but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        switch decoder.fleeceValue {
        case .string(let string):
            return string
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected String but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Blob.Type) throws -> Blob {
        switch decoder.fleeceValue {
        case .blob(let blob):
            return blob
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Blob but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Array<any Decodable>.Type) throws -> Array<any Decodable> {
        switch decoder.fleeceValue {
        case .array(let array):
            if let array = array.toArray() as? Array<any Decodable> {
                return array
            } else {
                throw CBLError.create(CBLError.decodingError, description: "Failed to decode array \(String(describing: array.toArray())) as Decodable")
            }
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Array but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Dictionary<String, any Decodable>.Type) throws -> Dictionary<String, any Decodable> {
        switch decoder.fleeceValue {
        case .dictionary(let dict):
            if let dict = dict.toDictionary() as? Dictionary<String, any Decodable> {
                return dict
            } else {
                throw CBLError.create(CBLError.decodingError, description: "Failed to decode dictionary \(String(describing: dict.toDictionary())) as Decodable")
            }
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Dictionary but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        switch type {
        case is Bool.Type:
            return try decode(Bool.self) as! T
        case is Int.Type:
            return try decode(Int.self) as! T
        case is Int8.Type:
            return try decode(Int8.self) as! T
        case is Int16.Type:
            return try decode(Int16.self) as! T
        case is Int32.Type:
            return try decode(Int32.self) as! T
        case is Int64.Type:
            return try decode(Int64.self) as! T
        case is UInt.Type:
            return try decode(UInt.self) as! T
        case is UInt8.Type:
            return try decode(UInt8.self) as! T
        case is UInt16.Type:
            return try decode(UInt16.self) as! T
        case is UInt32.Type:
            return try decode(UInt32.self) as! T
        case is UInt64.Type:
            return try decode(UInt64.self) as! T
        case is Float.Type:
            return try decode(Float.self) as! T
        case is Double.Type:
            return try decode(Double.self) as! T
        case is String.Type:
            return try decode(String.self) as! T
        case is Date.Type:
            return try decode(Date.self) as! T
        case is Blob.Type:
            return try decode(Blob.self) as! T
        case is Array<any Decodable>.Type:
            return try decode(Array<any Decodable>.self) as! T
        case is Dictionary<String, any Decodable>.Type:
            return try decode(Dictionary<String, any Decodable>.self) as! T
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected \(T.self) but found \(String(describing: decoder.fleeceValue))")
        }
    }
}

enum FleeceValue {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case float(Float)
    case double(Double)
    case string(String)
    case blob(Blob)
    case array(ArrayObject)
    case dictionary(DictionaryObject)
    
    private init?(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int64:
            self = .int(int)
        case let uint as UInt64:
            self = .uint(uint)
        case let float as Float:
            self = .float(float)
        case let double as Double:
            self = .double(double)
        case let string as String:
            self = .string(string)
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
    
    // This function will first try to strictly cast the `value` as the type `T`, or
    // whatever the appropriate representation for the type `T` is.
    // If `T` is none of the strict types in this list, it will defer to the
    // looser `init` above which will just succeed on the first successful
    // cast of `value`.
    //
    // The reason for attempting strict casting first is because, for example, most UInt can be
    // casted to Int. For any type which can be `as` casted to another, only loose casting would
    // mean it could get constructed as the wrong type.
    //
    // The early skip in this function exists to avoid going through every branch of both strict
    // and loose casting for user-defined structs.
    //
    init?<T>(_ value: Any, as type: T.Type) {
        // Early skip for types which are stored as Array or Dict (such as struct)
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
            if let v = value as? Int64 { self = .int(v) } else { return nil }
        case is Int16.Type:
            if let v = value as? Int16 { self = .int(Int64(v)) } else { return nil }
        case is Int32.Type:
            if let v = value as? Int32 { self = .int(Int64(v)) } else { return nil }
        case is Int64.Type:
            if let v = value as? Int64 { self = .int(v) } else { return nil }
        case is UInt.Type:
            if let v = value as? UInt64 { self = .uint(v) } else { return nil }
        case is UInt16.Type:
            if let v = value as? UInt16 { self = .uint(UInt64(v)) } else { return nil }
        case is UInt32.Type:
            if let v = value as? UInt32 { self = .uint(UInt64(v)) } else { return nil }
        case is UInt64.Type:
            if let v = value as? UInt64 { self = .uint(v) } else { return nil }
        case is Float.Type:
            if let v = value as? Float { self = .float(v) } else { return nil }
        case is Double.Type:
            if let v = value as? Double { self = .double(v) } else { return nil }
        case is String.Type:
            if let v = value as? String { self = .string(v) } else { return nil }
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

extension ISO8601DateFormatter {
    /// The variation of ISO8601 used by Couchbase.
    /// YYYY-mm-ddThh:mm:ss.SSSZ
    static let couchbase: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
