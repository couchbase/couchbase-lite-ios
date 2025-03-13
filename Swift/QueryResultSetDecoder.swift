//
//  QueryResultSetDecoder.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 12/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

internal struct QueryResultSetDecoder: Decoder {
    let resultSet: ResultSet
    
    var codingPath: [any CodingKey] = []
    
    var userInfo: [CodingUserInfoKey : Any] = [:]
    
    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        throw DecodingError.requiresUnkeyedContainer
    }
    
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let first = resultSet.next()
        return QueryResultSetDecodingContainer(resultSet: resultSet, next: first)
    }
    
    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.requiresUnkeyedContainer
    }
}

private struct QueryResultSetDecodingContainer : UnkeyedDecodingContainer {
    let resultSet: ResultSet
    var next: Result?
    
    init(resultSet: ResultSet, next: Result?) {
        self.resultSet = resultSet
        self.next = next
    }
    
    var codingPath: [any CodingKey] = []
    
    var count: Int? { nil }
    
    var isAtEnd: Bool { next == nil }
    
    var currentIndex: Int = 0
    
    func decodeNil() throws -> Bool {
        false
    }
    
    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        guard let next = self.next else {
            throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No value for index \(currentIndex)"))
        }
        let decoder = QueryResultDecoder(queryResult: next)
        let val = try T.init(from: decoder)
        currentIndex += 1
        self.next = resultSet.next()
        return val
    }
    
    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No nested container at index \(currentIndex)"))
    }
    
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No nested container at index \(currentIndex)"))
    }
    
    mutating func superDecoder() throws -> any Decoder {
        throw DecodingError.valueNotFound(.init(codingPath: codingPath, debugDescription: "No super container at index \(currentIndex)"))
    }
}
