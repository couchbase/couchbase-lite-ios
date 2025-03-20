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
            throw CBLError.create(CBLError.decodingError, description: "Value \(fleeceValue) is not a keyed container")
        }
    }
    
    public func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        switch fleeceValue {
        case .array(let arrayObject):
            FleeceArrayDecodingContainer(decoder: self, array: arrayObject)
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
        throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
    }
    
    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        guard let value = dict.value(forKey: key.stringValue) else {
            throw CBLError.create(CBLError.decodingError, description: "Dictionary is missing key '\(key.stringValue)'")
        }
        guard let fleeceValue = FleeceValue(value, as: T.self) else {
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
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
            fatalError("Failed to initialize FleeceValue<\(T.self)> with \(String(describing: value))")
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
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Bool but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Int.Type) throws -> Int {
        switch decoder.fleeceValue {
        case .int(let int):
            int
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Int but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: UInt.Type) throws -> UInt {
        switch decoder.fleeceValue {
        case .uint(let uint):
            uint
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected UInt but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Float.Type) throws -> Float {
        switch decoder.fleeceValue {
        case .float(let float):
            float
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Float but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Double.Type) throws -> Double {
        switch decoder.fleeceValue {
        case .double(let double):
            double
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Double but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: String.Type) throws -> String {
        switch decoder.fleeceValue {
        case .string(let string):
            string
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected String but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Data.Type) throws -> Data {
        switch decoder.fleeceValue {
        case .data(let data):
            data
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Data but found \(String(describing: decoder.fleeceValue))")
        }
    }
    
    func decode(_ type: Blob.Type) throws -> Blob {
        switch decoder.fleeceValue {
        case .blob(let blob):
            blob
        default:
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected Blob but found \(String(describing: decoder.fleeceValue))")
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
            throw CBLError.create(CBLError.decodingError, description: "Type mismatch: expected \(T.self) but found \(String(describing: decoder.fleeceValue))")
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
