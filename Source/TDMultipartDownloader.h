//
//  TDMultipartDownloader.h
//  TouchDB
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"
@class TDMultipartDocumentReader, TD_Database;


/** Downloads a remote CouchDB document in multipart format.
    Attachments are added to the database, but the document body isn't. */
@interface TDMultipartDownloader : TDRemoteRequest
{
    @private
    TDMultipartDocumentReader* _reader;
}

- (id) initWithURL: (NSURL*)url
          database: (TD_Database*)database
    requestHeaders: (NSDictionary *) requestHeaders
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@property (readonly) NSDictionary* document;

@end