//
//  TDMultipartUploader.h
//  TouchDB
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDRemoteRequest.h"
#import "TDMultipartStreamer.h"


@interface TDMultipartUploader : TDRemoteRequest

- (id) initWithURL: (NSURL *)url
          streamer: (TDMultipartStreamer*)streamer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion;

@end
