//
//  FleeceEncodable.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 11/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

public protocol FleeceEncodable : Encodable {
    func asNSObject() -> NSObject
}

extension Bool: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return NSNumber(booleanLiteral: self)
    }
}

extension Int: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension UInt: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Int8: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension UInt8: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Int16: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension UInt16: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Int32: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension UInt32: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Int64: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension UInt64: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Float: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension Double: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSNumber
    }
}

extension String: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSString
    }
}

extension Data: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSData
    }
}

extension Array: FleeceEncodable where Element: FleeceEncodable {
    public func asNSObject() -> NSObject {
        return self as NSArray
    }
}

extension Blob: FleeceEncodable {
    public func encode(to encoder: any Encoder) throws {
        throw Error.typeNotConformingToEncodable(Blob.self)
    }
    
    public func asNSObject() -> NSObject {
        return self.impl
    }
}
