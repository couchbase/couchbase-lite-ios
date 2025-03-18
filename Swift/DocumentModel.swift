//
//  DocumentModel.swift
//  CouchbaseLite
//
//  Created by Callum Birks on 27/02/2025.
//  Copyright © 2025 Couchbase. All rights reserved.
//

@attached(extension, conformances: DocumentObject, names: named(__ref))
public macro DocumentModel() = #externalMacro(module: "CBLSwiftMacros", type: "DocumentModelMacro")

public protocol DocumentObject {
    var __ref: DocumentId { get }
}

public typealias DocumentEncodable = Encodable & DocumentObject
public typealias DocumentDecodable = Decodable & DocumentObject
public typealias DocumentCodable = Codable & DocumentObject

@propertyWrapper
public final class DocumentId: Codable {
    internal var docID: String?
    internal var document: MutableDocument?

    public var wrappedValue: String? {
        get {
            return document == nil ? docID : document!.id
        }
        set {
            if document != nil {
                fatalError("Cannot change the document ID")
            }
            docID = newValue
        }
    }

    public var projectedValue: DocumentId { self }

    public init(wrappedValue: String?) {
        docID = wrappedValue
    }

    public convenience init(from decoder: Decoder) throws {
        if let dec = decoder as? DocumentDecoder {
            // If decoder has a document, we should assign it to self
            self.init(wrappedValue: dec.document.id)
            self.document = dec.document
        } else {
            // Otherwise, try to decode the ID string.
            let id = try String?.init(from: decoder)
            self.init(wrappedValue: id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        if let enc = encoder as? DocumentEncoder {
            if let doc = document {
                enc.document = doc
                return
            } else {
                document = MutableDocument(id: docID)
                enc.document = document!
                return
            }
        }
        // If encoder is not DocumentEncoder, encode the ID string.
        try docID?.encode(to: encoder)
    }
}
