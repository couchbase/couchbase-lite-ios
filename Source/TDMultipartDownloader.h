//
//  TDMultipartDownloader.h
//  TouchDB
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"
#import "TDMultipartReader.h"
@class TDDatabase, TDRevision, TDBlobStoreWriter;


/** Downloads a remote CouchDB document in multipart format.
    Attachments are added to the database, but the document body isn't. */
@interface TDMultipartDownloader : TDRemoteRequest <TDMultipartReaderDelegate>
{
    @private
    TDDatabase* _database;
    TDRevision* _revision;
    TDMultipartReader* _multipartReader;
    NSMutableData* _jsonBuffer;
    TDBlobStoreWriter* _curAttachment;
    NSMutableDictionary* _attachmentsByDigest;  // maps 'digest' property --> TDBlobStoreWriter
    NSDictionary* _document;
}

- (id) initWithURL: (NSURL*)url
          database: (TDDatabase*)database
          revision: (TDRevision*)revision
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@property (readonly) TDRevision* revision;
@property (readonly) NSDictionary* document;

@end