//
//  CBLMultipartUploader.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/5/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMultipartUploader.h"

@interface CBLMultipartUploader ()

@end

@implementation CBLMultipartUploader

- (instancetype) initWithURL: (NSURL *)url
             multipartWriter: (CBLMultipartUploaderMultipartWriterBlock)writer
                onCompletion: (CBLRemoteRequestCompletionBlock)onCompletion {
    Assert(writer);
    self = [super initWithMethod: @"PUT" 
                             URL: url 
                            body: nil
                    onCompletion: onCompletion];
    if (self) {
        _writer = [writer copy];
    }
    return self;
}


- (NSURLSessionTask*) createTaskInURLSession:(NSURLSession *)session {
    _currentWriter = _writer();

    // It's important to set a Content-Length header -- without this, CFNetwork won't know the
    // length of the body stream, so it has to send the body chunked. But unfortunately CouchDB
    // doesn't correctly parse chunked multipart bodies:
    // https://issues.apache.org/jira/browse/COUCHDB-1403
    SInt64 length = _currentWriter.length;
    Assert(length >= 0, @"HTTP multipart upload body has indeterminate length");
    [_request setValue: $sprintf(@"%lld", length) forHTTPHeaderField: @"Content-Length"];

    [_currentWriter openForURLRequest: _request];
    return [super createTaskInURLSession: session];
}


- (NSInputStream *) needNewBodyStream {
    LogTo(RemoteRequest, @"%@: Needs new body stream, resetting writer...", self);
    [_currentWriter close];
    _currentWriter = _writer();
    return [_currentWriter openForInputStream];
}


- (void) didFailWithError:(NSError *)error {
    if ($equal(error.domain, NSURLErrorDomain) && error.code == NSURLErrorRequestBodyStreamExhausted) {
        // The connection is complaining that the body input stream closed prematurely.
        // Check whether this is because the multipart writer got an error on _its_ input stream:
        NSError* writerError = _currentWriter.error;
        if (writerError)
            error = writerError;
    }
    [super didFailWithError: error];
}

@end
