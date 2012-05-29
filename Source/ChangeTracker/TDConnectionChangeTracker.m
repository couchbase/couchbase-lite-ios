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


#define kMaxRetries 4               // Number of retry attempts on failure to open TCP connection
#define kInitialRetryDelay 2.0      // Initial retry delay (doubles after every subsequent failure)


@implementation TDConnectionChangeTracker

- (BOOL) start {
    [super start];
    _inputBuffer = [[NSMutableData alloc] init];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    request.timeoutInterval = 6.02e23;
    
    // Add headers.
    [self.requestHeaders enumerateKeysAndObjectsUsingBlock: ^(id key, id value, BOOL *stop) {
        [request setValue: value forHTTPHeaderField: key];
    }];
    
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
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(start)
                                               object: nil];    // cancel pending retries
    if (_connection)
        [_connection cancel];
    [super stop];
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _retryCount = 0;  // successful TCP connection
    TDStatus status = (TDStatus) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(ChangeTracker, @"%@: Got response, status %d", self, status);
    if (TDStatusIsError(status)) {
        Warn(@"%@: Got status %i", self, status);
        self.error = TDStatusToNSError(status, self.changesFeedURL);
        [self stop];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    LogTo(ChangeTrackerVerbose, @"%@: Got %lu bytes", self, (unsigned long)data.length);
    [_inputBuffer appendData: data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    // This is called for an error with the socket, _not_ an HTTP error status.
    // In this case we should retry, since the network might be flaky.
    if (++_retryCount <= kMaxRetries) {
        [self clearConnection];
        NSTimeInterval retryDelay = kInitialRetryDelay * (1 << (_retryCount-1));
        Log(@"%@: Connection error, retrying in %.1f sec: %@",
            self, retryDelay, error.localizedDescription);
        [self performSelector: @selector(start) withObject: nil afterDelay: retryDelay];
    } else {
        Warn(@"%@: Can't connect, giving up: %@", self, error);
        self.error = error;
        [self stopped];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // Now parse the entire response as a JSON document:
    NSData* input = [_inputBuffer retain];
    LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
    NSInteger numChanges = [self receivedPollResponse: input];
    if (numChanges < 0)
        [self setUpstreamError: @"Unparseable server response"];
    [input release];
    
    [self clearConnection];
    
    // Poll again if there was no error, and either we're in longpoll mode or it looks like we
    // ran out of changes due to a _limit rather than because we hit the end.
    if (numChanges > 0 && (_mode == kLongPoll || numChanges == (NSInteger)_limit))
        [self start];       // Next poll...
    else
        [self stopped];
}

@end
