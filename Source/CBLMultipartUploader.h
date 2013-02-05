//
//  CBLMultipartUploader.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLRemoteRequest.h"
#import "CBLMultipartWriter.h"


@interface CBLMultipartUploader : CBLRemoteRequest
{
    @private
    CBLMultipartWriter* _multipartWriter;
}

- (instancetype) initWithURL: (NSURL *)url
                    streamer: (CBLMultipartWriter*)streamer
              requestHeaders: (NSDictionary *) requestHeaders
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion;

@end
