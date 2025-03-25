//
//  DocumentModel.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 27/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

internal func getDocumentRef(object: any AnyObject) -> DocumentID? {
    let mirror = Mirror(reflecting: object)
    for child in mirror.children {
        if let docID = child.value as? DocumentID {
            return docID
        }
    }
    return nil
}

public typealias DocumentEncodable = Encodable & AnyObject
public typealias DocumentDecodable = Decodable & AnyObject
public typealias DocumentCodable = Codable & AnyObject

@propertyWrapper
public final class DocumentID: Codable {
    internal var docID: String?
    internal var revID: String?

    public var wrappedValue: String? {
        get {
            return docID
        }
        set {
            if revID != nil {
                fatalError("Cannot change the document ID of an existing document")
            }
            docID = newValue
        }
    }

    public init(wrappedValue: String?) {
        docID = wrappedValue
    }

    public convenience init(from decoder: Decoder) throws {
        if let dec = decoder as? DocumentDecoder {
            // If decoder has a document, we should assign it to self
            self.init(wrappedValue: dec.document.id)
            self.revID = dec.document.revisionID
        } else {
            // Otherwise, try to decode the ID string.
            let id = try String?.init(from: decoder)
            self.init(wrappedValue: id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if encoder is DocumentEncoder {
            // Doc ID doesn't get encoded to document fields
            return
        }
        // If encoder is not DocumentEncoder, encode the ID string.
        if let docID = docID {
            try docID.encode(to: encoder)
        } else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}
