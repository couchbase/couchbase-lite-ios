//
//  TDMultipartUploader.h
//  TouchDB
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"
#import "TDMultipartWriter.h"


@interface TDMultipartUploader : TDRemoteRequest
{
    @private
    TDMultipartWriter* _multipartWriter;
}

- (id) initWithURL: (NSURL *)url
          streamer: (TDMultipartWriter*)streamer
    requestHeaders: (NSDictionary *) requestHeaders
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@end
