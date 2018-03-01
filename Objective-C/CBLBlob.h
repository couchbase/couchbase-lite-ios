//
//  CBLBlob.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/** 
 A CBLBlob contains arbitrary binary data, tagged with a MIME type.
 Blobs can be arbitrarily large, and their data is loaded only on demand (when the `content`
 or `contentStream` properties are accessed), not when the document is loaded.
 The document's raw JSON form only contains the CBLBlob's metadata (type, length and a digest of
 the data) in a small object. The data itself is stored externally to the document, keyed by
 the digest.
 */
@interface CBLBlob : NSObject

/** 
 Initializes a CBLBlob with the given in-memory data.
 
 @param contentType The type of content this CBLBlob will represent.
 @param data The data that this CBLBlob will contain.
 @return The CBLBlob object.
 */
- (instancetype) initWithContentType: (NSString *)contentType
                                data: (NSData *)data;

/** 
 Initializes a CBLBlob with the given stream of data.
 
 @param contentType The type of content this CBLBlob will represent.
 @param stream The stream of data that this CBLBlob will consume.
 @return The CBLBlob object.
 */
- (instancetype) initWithContentType: (NSString *)contentType
                       contentStream: (NSInputStream *)stream;

/** 
 Initializes a CBLBlob with the contents of a file.
 
 @param contentType The type of content this CBLBlob will represent.
 @param fileURL A URL to a file containing the data that this CBLBlob will represent.
 @param error On return, the error if any.
 @return The CBLBlob object.
 */
- (nullable instancetype) initWithContentType: (NSString *)contentType
                                      fileURL: (NSURL*)fileURL
                                        error: (NSError**)error;

/** The -init method is not available. */
- (instancetype) init NS_UNAVAILABLE;

/** Gets the contents of a CBLBlob as a block of memory.
    Not recommended for very large blobs, as it may be slow and use up lots of RAM. */
@property (readonly, nonatomic, nullable) NSData* content;

/** A stream of the content of a CBLBlob.
    The caller is responsible for opening the stream, and closing it when finished. */
@property (readonly, nonatomic, nullable) NSInputStream *contentStream;

/** The type of content this CBLBlob represents; by convention this is a MIME type. */
@property (readonly, nonatomic, nullable) NSString* contentType;

/** The binary length of this CBLBlob. */
@property (readonly, nonatomic) uint64_t length;

/** The cryptographic digest of this CBLBlob's contents, which uniquely identifies it. */
@property (readonly, nonatomic, nullable) NSString* digest;

/** The metadata associated with this CBLBlob */
@property (readonly, nonatomic) NSDictionary<NSString*,id>* properties;

@end

NS_ASSUME_NONNULL_END
