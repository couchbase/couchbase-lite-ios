//
//  DocumentID.swift
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
