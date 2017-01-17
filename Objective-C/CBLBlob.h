//
//  CBLBlob.h
//  CouchbaseLite
//
//  Created by Jim Borden on 2017/01/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLBlob : NSObject

/**
 Gets the contents of a CBLBlob as a block of memory (warning: 
 if this blob gets its contents from a slow stream this operation
 will block until the stream is fully read)
 */
@property (readonly, nonatomic, nullable) NSData* content;

/**
 Gets a stream to the content of a CBLBlob
 */
@property (readonly, nonatomic) NSInputStream *contentStream;

/**
 Gets the type of content this CBLBlob represents
 */
@property (readonly, nonatomic) NSString* contentType;

/**
 Gets the binary length of this CBLBlob
 */
@property (readonly) NSInteger length;

/**
 Gets the digest of this CBLBlob's contents
 */
@property (readonly, nullable) NSString* digest;

/**
 Gets the metadata associated with this CBLBlob
 */
@property (readonly, nonatomic) NSDictionary* properties;

/**
 Initializes a CBLBlob with the given in-memory data
 @param contentType The type of content this CBLBlob will represent
 @param data The data that this CBLBlob will contain
 */
- (instancetype) initWithContentType:(NSString *)contentType
                                data:(NSData *) data;

/**
 Initializes a CBLBlob with the given stream of data
 @param contentType The type of content this CBLBlob will represent
 @param stream The stream of data that this CBLBlob will consume
 */
- (instancetype) initWithContentType:(NSString *)contentType
                       contentStream:(NSInputStream *)stream;

/**
 Initializes a CBLBlob with the given in-memory data
 @param contentType The type of content this CBLBlob will represent
 @param url A url to a file containing the data that this CBLBlob will represent
 */
- (instancetype) initWithContentType:(NSString *)contentType
                             fileURL:(NSURL*)url;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
