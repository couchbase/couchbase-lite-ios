//
//  CBLAttachmentDownloader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/3/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
@class CBLDatabase;

typedef void (^CBLAttachmentDownloaderProgressBlock)(uint64_t bytesRead,
                                                     uint64_t contentLength,
                                                     NSError* error);

@interface CBLAttachmentDownloader : CBLRemoteRequest

- (instancetype) initWithDbURL: (NSURL*)dbURL
                      database: (CBLDatabase*)database
                      document: (NSDictionary*)doc
                attachmentName: (NSString*)name
                      progress: (NSProgress*)progress
                  onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

#if DEBUG
extern BOOL CBLAttachmentDownloaderFakeTransientFailures;
@property BOOL fakeTransientFailure;    // for testing only; causes one fake failure during DL
#endif

@end
