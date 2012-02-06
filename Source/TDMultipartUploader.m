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
          streamer: (TDMultipartWriter*)streamer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    Assert(streamer);
    return [super initWithMethod: @"PUT" URL: url body: streamer onCompletion: onCompletion];
}

- (void)dealloc {
    [_streamer release];
    [super dealloc];
}

- (void) setupRequest: (NSMutableURLRequest*)request withBody: (id)body {
    _streamer = [body retain];
    [_streamer openForURLRequest: request];
    [request setValue: $sprintf(@"%llu", _streamer.length) forHTTPHeaderField: @"Content-Length"];
    // It's important to set a Content-Length header -- without this, CFNetwork won't know the
    // length of the body stream, so it has to send the body chunked. But unfortunately CouchDB
    // doesn't correctly parse chunked multipart bodies:
    // https://issues.apache.org/jira/browse/COUCHDB-1403
}

@end
