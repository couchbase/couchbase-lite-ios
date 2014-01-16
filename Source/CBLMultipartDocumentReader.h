//
//  CBLMultipartDocumentReader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/29/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLMultipartReader.h"
#import "CBLStatus.h"
@class CBLDatabase, CBL_Revision, CBL_BlobStoreWriter, CBLMultipartDocumentReader;


typedef void(^CBLMultipartDocumentReaderCompletionBlock)(CBLMultipartDocumentReader*);


@interface CBLMultipartDocumentReader : NSObject
{
    @private
    CBLDatabase* _database;
    CBLStatus _status;
    CBLMultipartReader* _multipartReader;
    NSMutableData* _jsonBuffer;
    BOOL _jsonCompressed;
    CBL_BlobStoreWriter* _curAttachment;
    NSMutableDictionary* _attachmentsByName;      // maps attachment name --> CBL_BlobStoreWriter
    NSMutableDictionary* _attachmentsByDigest;    // maps attachment MD5 --> CBL_BlobStoreWriter
    NSMutableDictionary* _document;
    CBLMultipartDocumentReaderCompletionBlock _completionBlock;
}

// synchronous:
+ (NSDictionary*) readData: (NSData*)data
                   headers: (NSDictionary*)headers
                toDatabase: (CBLDatabase*)database
                    status: (CBLStatus*)outStatus;

// asynchronous:
+ (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
              toDatabase: (CBLDatabase*)database
                    then: (CBLMultipartDocumentReaderCompletionBlock)completionBlock;

- (instancetype) initWithDatabase: (CBLDatabase*)database;

@property (readonly, nonatomic) CBLStatus status;
@property (readonly, nonatomic) NSDictionary* document;
@property (readonly, nonatomic) NSUInteger attachmentCount;

- (BOOL) setHeaders: (NSDictionary*)headers;

- (BOOL) appendData: (NSData*)data;

- (CBLStatus) readStream: (NSInputStream*)stream
                 headers: (NSDictionary*)headers
                    then: (CBLMultipartDocumentReaderCompletionBlock)completionBlock;

- (BOOL) finish;

@end
