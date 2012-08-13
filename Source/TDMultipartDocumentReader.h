//
//  TDMultipartDocumentReader.h
//  
//
//  Created by Jens Alfke on 3/29/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultipartReader.h"
#import <TouchDB/TDStatus.h>
@class TDDatabase, TDRevision, TDBlobStoreWriter, TDMultipartDocumentReader;


typedef void(^TDMultipartDocumentReaderCompletionBlock)(TDMultipartDocumentReader*);


@interface TDMultipartDocumentReader : NSObject <TDMultipartReaderDelegate, NSStreamDelegate>
{
    @private
    TDDatabase* _database;
    TDStatus _status;
    TDMultipartReader* _multipartReader;
    NSMutableData* _jsonBuffer;
    TDBlobStoreWriter* _curAttachment;
    NSMutableDictionary* _attachmentsByName;      // maps attachment name --> TDBlobStoreWriter
    NSMutableDictionary* _attachmentsByDigest;    // maps attachment MD5 --> TDBlobStoreWriter
    NSMutableDictionary* _document;
    TDMultipartDocumentReaderCompletionBlock _completionBlock;
}

// synchronous:
+ (NSDictionary*) readData: (NSData*)data
                    ofType: (NSString*)contentType
                toDatabase: (TDDatabase*)database
                    status: (TDStatus*)outStatus;

// asynchronous:
+ (TDStatus) readStream: (NSInputStream*)stream
                 ofType: (NSString*)contentType
             toDatabase: (TDDatabase*)database
                   then: (TDMultipartDocumentReaderCompletionBlock)completionBlock;

- (id) initWithDatabase: (TDDatabase*)database;

@property (readonly, nonatomic) TDStatus status;
@property (readonly, nonatomic) NSDictionary* document;
@property (readonly, nonatomic) NSUInteger attachmentCount;

- (BOOL) setContentType: (NSString*)contentType;

- (BOOL) appendData: (NSData*)data;

- (TDStatus) readStream: (NSInputStream*)stream
                 ofType: (NSString*)contentType
                   then: (TDMultipartDocumentReaderCompletionBlock)completionBlock;

- (BOOL) finish;

@end
