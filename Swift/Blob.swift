//
//  Blob.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

import Foundation

/// Blob contains arbitrary binary data, tagged with a MIME type.
/// Blobs can be arbitrarily large, and their data is loaded only on demand (when the `content`
/// or `contentStream` properties are accessed), not when the document is loaded.
/// The document's raw JSON form only contains the Blob's metadata (type, length and a digest of
/// the data) in a small object. The data itself is stored externally to the document, keyed by
/// the digest.
public final class Blob: Equatable, Hashable {
    
    /// Value of type property for blob object
    public static let blobType: String = kCBLBlobType
    
    /// Blob dict property containing a blobType of the data.
    public static let typeProperty: String = kCBLTypeProperty
    
    /// Blob dict property containing a digest of the data.
    public static let blobDigestProperty: String = kCBLBlobDigestProperty
    
    /// Blob dict property containing a length of the data.
    public static let blobLengthProperty: String = kCBLBlobLengthProperty
    
    /// Blob dict property containing a content type of the data.
    public static let blobContentType: String = kCBLBlobContentTypeProperty
    
    /// Initializes a Blob with the given in-memory data.
    ///
    /// - Parameters:
    ///   - contentType: The type of content this Blob will represent.
    ///   - data: The data that this Blob will contain.
    public convenience init(contentType: String, data: Data) {
        self.init(CBLBlob(contentType: contentType, data: data))
    }
    
    /// Initializes a Blob with the given stream of data.
    ///
    /// - Parameters:
    ///   - contentType: The type of content this Blob will represent.
    ///   - contentStream: The stream of data that this Blob will consume.
    public convenience init(contentType: String, contentStream: InputStream) {
        self.init(CBLBlob(contentType: contentType, contentStream: contentStream))
    }
    
    /// Initializes a Blob with the contents of a file.
    ///
    /// - Parameters:
    ///   - contentType: The type of content this Blob will represent.
    ///   - fileURL: A URL to a file containing the data that this Blob will represent.
    /// - Throws: An error on a failure.
    public convenience init(contentType: String, fileURL: URL) throws {
        self.init(try CBLBlob(contentType: contentType, fileURL: fileURL))
    }
    
    /// Gets the contents of a Blob as a block of memory.
    /// Not recommended for very large blobs, as it may be slow and use up lots of RAM.
    public var content: Data? {
        return impl.content
    }
    
    /// A stream of the content of a Blob.
    /// The caller is responsible for opening the stream, and closing it when finished.
    public var contentStream: InputStream? {
        return impl.contentStream
    }
    
    /// The type of content this Blob represents; by convention this is a MIME type.
    public var contentType: String? {
        return impl.contentType
    }
    
    /// The binary length of this Blob.
    public var length: UInt64 {
        return impl.length
    }
    
    /// The cryptographic digest of this Blob's contents, which uniquely identifies it.
    public var digest: String? {
        return impl.digest
    }
    
    /// The metadata associated with this Blob
    public var properties: [String: Any] {
        return impl.properties
    }
    
    // MARK: Equality
    
    /// Equal to operator for comparing two Blob objects.
    public static func == (blob1: Blob, blob2: Blob) -> Bool {
        return blob1.impl == blob2.impl
    }
    
    // MARK: Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(impl.hash)
    }
    
    // MARK: toJSON
    
    /// Returns a dictionary representation of the blob object in JSON string format. The dictionary
    /// will contain only metadata information without data.
    
    /// If Blob is not saved in the database which means that it doesn’t have digest information,
    /// calling toJSON() will not be allowed and it will throw an NSInternalInconsistencyException.
    public func toJSON() -> String {
        return impl.toJSON()
    }
    
    /// Return whether the given dictionary represents Blob or not
    public static func isBlob(properties: [String: Any]) -> Bool {
        return CBLBlob.isBlob(properties)
    }
    
    // MARK: Internal
    
    init(_ impl: CBLBlob) {
        self.impl = impl
        impl.swiftObject = self
    }
    
    deinit {
        impl.swiftObject = nil
    }
    
    let impl: CBLBlob
    
}

