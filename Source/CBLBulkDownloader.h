//
//  CBLBulkDownloader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/20/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
@class CBLDatabase, CBL_Revision;


typedef void (^CBLBulkDownloaderDocumentBlock)(NSDictionary*);


/** Handles a _bulk_get request, to pull updates to multiple docs.
    (This request is not in the standard CouchDB API, but Sync Gateway supports it.) */
@interface CBLBulkDownloader : CBLRemoteRequest

- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                     revisions: (NSArray*)revs
                   attachments: (BOOL)attachments
                    onDocument: (CBLBulkDownloaderDocumentBlock)onDocument
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

@end
