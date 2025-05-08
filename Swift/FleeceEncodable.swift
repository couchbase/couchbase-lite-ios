//
//  FleeceEncodable.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 05/03/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

import CouchbaseLiteSwift_Private

public protocol FleeceEncodable {
    func encode(to encoder: FleeceEncoder) throws
}

extension Bool : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeBool(self)
    }
}

extension Int : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeInt(self)
    }
}

extension UInt : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeUInt(self)
    }
}

extension Float : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeFloat(self)
    }
}

extension Double : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeDouble(self)
    }
}

extension String : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeString(self)
    }
}

extension Data : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeData(self)
    }
}

extension Array<any FleeceEncodable> : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeArray(self)
    }
}

extension Dictionary<String, any FleeceEncodable> : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeDictionary(self)
    }
}

extension Blob : FleeceEncodable {
    public func encode(to encoder: FleeceEncoder) throws {
        try encoder.writeBlob(self)
    }
}
