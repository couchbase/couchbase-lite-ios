//
//  TDConnectionChangeTracker.m
//  TouchDB
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>

#import "TDConnectionChangeTracker.h"
#import "TDMisc.h"
#import "TDStatus.h"


@implementation TDConnectionChangeTracker

- (BOOL) start {
    [super start];
    // For some reason continuous mode doesn't work with CFNetwork.
    if (_mode == kContinuous)
        _mode = kLongPoll;
    
    _inputBuffer = [[NSMutableData alloc] init];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    request.timeoutInterval = 6.02e23;
    
    _connection = [[NSURLConnection connectionWithRequest: request delegate: self] retain];
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, request.URL);
    return YES;
}


- (void) clearConnection {
    [_connection autorelease];
    _connection = nil;
    [_inputBuffer release];
    _inputBuffer = nil;
}


- (void) stopped {
    LogTo(ChangeTracker, @"%@: Stopped", self);
    [self clearConnection];
    [super stopped];
}


- (void) stop {
    if (_connection) {
        [_connection cancel];
        [super stop];
    }
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    TDStatus status = (TDStatus) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(ChangeTracker, @"%@: Got response, status %d", self, status);
    if (TDStatusIsError(status)) {
        Warn(@"%@: Got status %i", self, status);
        self.error = TDStatusToNSError(status, self.changesFeedURL);
        [self stop];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(ChangeTracker, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    [_inputBuffer appendData: data];
    
    if (_mode == kContinuous) {
        // In continuous mode, break input into lines and parse each as JSON:
        for (;;) {
            const char* start = _inputBuffer.bytes;
            const char* eol = memchr(start, '\n', _inputBuffer.length);
            if (!eol)
                break;  // Wait till we have a complete line
            ptrdiff_t lineLength = eol - start;
            NSData* chunk = [[[NSData alloc] initWithBytes: start
                                                       length: lineLength] autorelease];
            [_inputBuffer replaceBytesInRange: NSMakeRange(0, lineLength + 1)
                                    withBytes: NULL length: 0];
            // Finally! Send the line to the database to parse:
            [self receivedChunk: chunk];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    LogTo(ChangeTracker, @"%@: Got error %@", self, error);
    self.error = error;
    [self stopped];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (_mode != kContinuous) {
        // In non-continuous mode, now parse the entire response as a JSON document:
        NSData* input = [_inputBuffer retain];
        LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
        BOOL responseOK = [self receivedPollResponse: input];
        if (!responseOK)
            [self setUpstreamError: @"Unparseable server response"];
        [input release];
        
        [self clearConnection];
        if (_mode == kLongPoll && responseOK)
            [self start];       // Next poll...
        else
            [self stopped];
    } else {
        [self stopped];
    }
}

@end
