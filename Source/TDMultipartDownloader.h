//
//  TDMultipartDownloader.h
//  TouchDB
//
//  Created by Jens Alfke on 1/31/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"
@class TDMultipartDocumentReader, TDDatabase;


/** Downloads a remote CouchDB document in multipart format.
    Attachments are added to the database, but the document body isn't. */
@interface TDMultipartDownloader : TDRemoteRequest
{
    @private
    TDMultipartDocumentReader* _reader;
}

- (id) initWithURL: (NSURL*)url
          database: (TDDatabase*)database
        authorizer: (id<TDAuthorizer>)authorizer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@property (readonly) NSDictionary* document;

@end