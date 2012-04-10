//
//  TDMultipartUploader.m
//  TouchDB
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDMultipartUploader.h"


@implementation TDMultipartUploader

- (id) initWithURL: (NSURL *)url
          streamer: (TDMultipartWriter*)streamer
        authorizer: (id<TDAuthorizer>)authorizer
      onCompletion: (TDRemoteRequestCompletionBlock)onCompletion
{
    Assert(streamer);
    return [super initWithMethod: @"PUT" URL: url body: streamer
                      authorizer: authorizer
                    onCompletion: onCompletion];
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
