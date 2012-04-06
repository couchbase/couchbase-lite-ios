//
//  TDMultipartDocumentReader.h
//  
//
//  Created by Jens Alfke on 3/29/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultipartReader.h"
#import "TDStatus.h"
@class TDDatabase, TDRevision, TDBlobStoreWriter;


@interface TDMultipartDocumentReader : NSObject <TDMultipartReaderDelegate>
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
}

+ (NSDictionary*) readData: (NSData*)data
                    ofType: (NSString*)contentType
                toDatabase: (TDDatabase*)database
                    status: (TDStatus*)outStatus;

- (id) initWithDatabase: (TDDatabase*)database;

@property (readonly, nonatomic) TDStatus status;
@property (readonly, nonatomic) NSDictionary* document;
@property (readonly, nonatomic) NSUInteger attachmentCount;

- (BOOL) setContentType: (NSString*)contentType;

- (BOOL) appendData: (NSData*)data;

- (BOOL) finish;

@end
