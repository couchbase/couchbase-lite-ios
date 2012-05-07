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
    TDMultipartWriter* _streamer;
}

- (id) initWithURL: (NSURL *)url
          streamer: (TDMultipartWriter*)streamer
        authorizer: (id<TDAuthorizer>)authorizer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@end
