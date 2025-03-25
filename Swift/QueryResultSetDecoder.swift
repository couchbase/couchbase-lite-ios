//
//  QueryResultSetDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 12/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//
import CouchbaseLiteSwift_Private

internal struct QueryResultSetDecoder: Decoder {
    let resultSet: ResultSet
    let dataKey: String?
    
    init(resultSet: ResultSet, dataKey: String? = nil) {
        self.resultSet = resultSet
        self.dataKey = dataKey
    }
    
    var codingPath: [any CodingKey] = []
    
    public var userInfo: [CodingUserInfoKey : Any] { return [:] }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        throw CBLError.create(CBLError.decodingError, description: "ResultSet decoding requires an unkeyed container")
    }
    
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let first = resultSet.next()
        return QueryResultSetDecodingContainer(resultSet: resultSet, dataKey: dataKey, next: first)
    }
    
    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw CBLError.create(CBLError.decodingError, description: "ResultSet decoding requires an unkeyed container")
    }
}

private struct QueryResultSetDecodingContainer : UnkeyedDecodingContainer {
    let resultSet: ResultSet
    let dataKey: String?
    var next: Result?
    
    init(resultSet: ResultSet, dataKey: String?, next: Result?) {
        self.resultSet = resultSet
        self.dataKey = dataKey
        self.next = next
    }
    
    var codingPath: [any CodingKey] = []
    
    var count: Int? { return nil }
    
    var isAtEnd: Bool { return next == nil }
    
    var currentIndex: Int = 0
    
    func decodeNil() throws -> Bool {
        return false
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        guard let next = self.next else {
            throw CBLError.create(CBLError.decodingError, description: "No value at index \(currentIndex) in ResultSet")
        }
        let decoder = QueryResultDecoder(queryResult: next, dataKey: dataKey)
        let val = try T.init(from: decoder)
        currentIndex += 1
        self.next = resultSet.next()
        return val
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw CBLError.create(CBLError.decodingError, description: "No nested container in ResultSet")
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw CBLError.create(CBLError.decodingError, description: "No nested container in ResultSet")
    }
    
    mutating func superDecoder() throws -> any Decoder {
        throw CBLError.create(CBLError.decodingError, description: "No nested container in ResultSet")
    }
}
