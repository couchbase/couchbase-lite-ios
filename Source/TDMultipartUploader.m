//
//  TDMultipartUploader.m
//  TouchDB
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMultipartUploader.h"


@implementation TDMultipartUploader

- (id) initWithURL: (NSURL *)url
          streamer: (TDMultipartStreamer*)streamer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    Assert(streamer);
    return [super initWithMethod: @"PUT" URL: url body: streamer onCompletion: onCompletion];
}

- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    UInt64 length;
#if 1
    request.HTTPBodyStream = body;
    length = [body length];
#else  // alternate method, generating the data up front, just here for debugging
    NSMutableData* data = [NSMutableData data];
    uint8_t* buffer = malloc(32768);
    NSInteger bytesRead;
    [body open];
    do {
        bytesRead = [body read: buffer maxLength: 32768];
        if (bytesRead > 0)
            [data appendBytes: buffer length: bytesRead];
    } while (bytesRead > 0);
    free(buffer);
    [body close];
    Assert(bytesRead == 0);
    request.HTTPBody = data;
    length = data.length;
#endif
    [request setValue: $sprintf(@"multipart/related; boundary=\"%@\"", [body boundary])
             forHTTPHeaderField: @"Content-Type"];
    // It's important to set a Content-Length header -- without this, CFNetwork won't know the
    // length of the body stream, so it has to send the body chunked. But unfortunately CouchDB
    // doesn't seem to be able to parse chunked multipart bodies, judging by the mysterious Erlang
    // exceptions I got every time I tried.
    [request setValue: $sprintf(@"%llu", length) forHTTPHeaderField: @"Content-Length"];
}

@end
