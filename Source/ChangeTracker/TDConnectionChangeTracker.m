//
//  CouchConnectionChangeTracker.m
//  CouchCocoa
//
//  Created by Jens Alfke on 12/1/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//
// <http://wiki.apache.org/couchdb/HTTP_database_API#Changes>

#import "TDConnectionChangeTracker.h"


@implementation TDConnectionChangeTracker

- (BOOL) start {
    // For some reason continuous mode doesn't work with CFNetwork.
    if (_mode == kContinuous)
        _mode = kLongPoll;
    
    _inputBuffer = [[NSMutableData alloc] init];
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL: self.changesFeedURL];
    request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    request.timeoutInterval = 6.02e23;
    
    _connection = [[NSURLConnection connectionWithRequest: request delegate: self] retain];
    [_connection start];
    LogTo(ChangeTracker, @"%@: Started... <%@>", self, request.URL);
    return YES;
}


- (void) clearConnection {
    [_connection autorelease];
    _connection = nil;
    [_inputBuffer release];
    _inputBuffer = nil;
    _status = 0;
}


- (void) stopped {
    LogTo(ChangeTracker, @"%@: Stopped", self);
    [self clearConnection];
    [super stopped];
}


- (void) stop {
    [_connection cancel];
    [super stop];
}


- (void)connection:(NSURLConnection *)connection
        didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    LogTo(ChangeTracker, @"%@: didReceiveAuthenticationChallenge", self);
    if (challenge.previousFailureCount == 0) {
        NSURLCredential* credential = self.authCredential;
        if (credential) {
            [challenge.sender useCredential: credential forAuthenticationChallenge: challenge];
            return;
        }
    }
    // give up
    [challenge.sender cancelAuthenticationChallenge: challenge];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    _status = (int) ((NSHTTPURLResponse*)response).statusCode;
    LogTo(ChangeTracker, @"%@: Got response, status %d", self, _status);
    if (_status >= 300) {
        Warn(@"%@: Got status %i", self, _status);
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
            const char* eol = strnstr(start, "\n", _inputBuffer.length);
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
    Warn(@"%@: Got error %@", self, error);
    [self stopped];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (_mode != kContinuous) {
        int status = _status;
        NSData* input = [_inputBuffer retain];
        LogTo(ChangeTracker, @"%@: Got entire body, %u bytes", self, (unsigned)input.length);
        BOOL responseOK = [self receivedPollResponse: input];
        [input release];
        
        [self clearConnection];
        if (_mode == kLongPoll && status == 200 && responseOK)
            [self start];       // Next poll...
        else
            [self stopped];
    } else {
        [self stopped];
    }
}

@end
