//
//  TDHTTPResponse.m
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDHTTPResponse.h"
#import "TDHTTPConnection.h"
#import "TDListener.h"
#import "TDRouter.h"
#import "TDBody.h"

#import "Logging.h"


@interface TDHTTPResponse ()
- (void) onResponseReady: (TDResponse*)response;
- (void) onDataAvailable: (NSData*)data;
- (void) onFinished;
@end



@implementation TDHTTPResponse


- (id) initWithRouter: (TDRouter*)router forConnection:(TDHTTPConnection*)connection {
    self = [super init];
    if (self) {
        _router = [router retain];
        _connection = connection;
        router.onResponseReady = ^(TDResponse* r) {
            [self onResponseReady: r];
        };
        router.onDataAvailable = ^(NSData* data) {
            [self onDataAvailable: data];
        };
        router.onFinished = ^{
            [self onFinished];
        };
        
        // Run the router, synchronously:
        LogTo(TDListenerVerbose, @"%@: Starting...", self);
        [_connection.listener onServerThread: ^{[router start];}];
        _chunked = !_finished;
    }
    return self;
}

- (void)dealloc {
    [_router release];
    [_response release];
    [_data release];
    [super dealloc];
}


- (NSString*) description {
    return [NSString stringWithFormat: @"Response[%@ %@]",
                                        _router.request.HTTPMethod, _router.request.URL.path];
}


/**
 * If you don't know the content-length in advance,
 * implement this method in your custom response class and return YES.
 **/
- (BOOL) isChunked {
    return _chunked;
}


- (BOOL) delayResponeHeaders {
    return _chunked && !_response;
}


- (void) onResponseReady: (TDResponse*)response {
    _response = [response retain];
    LogTo(TDListener, @"    %@ --> %i", self, _response.status);
    if (_chunked)
        [_connection responseHasAvailableData: self];
}


- (NSInteger) status {
    return _response.status;
}

- (NSDictionary *) httpHeaders {
    return _response.headers;
}


- (void) onDataAvailable: (NSData*)data {
    LogTo(TDListenerVerbose, @"%@ adding %u bytes", self, (unsigned)data.length);
    if (_data)
        [_data appendData: data];
    else
        _data = [data mutableCopy];
    if (_chunked)
        [_connection responseHasAvailableData: self];
}


- (UInt64) offset                        {return _offset;}
- (void) setOffset: (UInt64)offset       {_offset = offset;}

- (UInt64) contentLength {
    if (!_finished)
        return 0;
    return _dataOffset + _data.length;
}


- (NSData*) readDataOfLength: (NSUInteger)length {
    NSAssert(_offset >= _dataOffset, @"Invalid offset %llu, min is %llu", _offset, _dataOffset);
    NSRange range;
    range.location = (NSUInteger)(_offset - _dataOffset);
    if (range.location >= _data.length)
        return nil;
    NSUInteger bytesAvailable = _data.length - range.location;
    range.length = MIN(length, bytesAvailable);
    NSData* result = [_data subdataWithRange: range];
    _offset += range.length;
    if (range.length == bytesAvailable) {
        // Client has read all of the available data, so we can discard it
        _dataOffset += _data.length;
        [_data autorelease];
        _data = nil;
    }
    LogTo(TDListenerVerbose, @"%@ sending %u bytes", self, result.length);
    return result;
}


- (BOOL) isDone {
    return _finished;
}


- (void) onFinished {
    if (_finished)
        return;
    _finished = true;

    LogTo(TDListenerVerbose, @"%@ Finished!", self);

    // Break cycles:
    _router.onResponseReady = nil;
    _router.onDataAvailable = nil;
    _router.onFinished = nil;

    if (!_chunked) {
        // Response finished immediately, before the connection asked for any data, so we're free
        // to massage the response:
        int status = _response.status;
        if (status >= 300 && _data.length == 0) {
            // Put a generic error message in the body:
            NSString* errorMsg;
            switch (status) {
                case 404:   errorMsg = @"not_found"; break;
                    // TODO: There are more of these to add; see error_info() in couch_httpd.erl
                default:
                    errorMsg = [NSHTTPURLResponse localizedStringForStatusCode: status];
            }
            NSString* responseStr = [NSString stringWithFormat: @"{\"status\": %i, \"error\":\"%@\"}\n",
                                                                 status, errorMsg];
            [self onDataAvailable: [responseStr dataUsingEncoding: NSUTF8StringEncoding]];
            [_response.headers setObject: @"text/plain; encoding=UTF-8" forKey: @"Content-Type"];
        } else {
#if DEBUG
            BOOL pretty = YES;
#else
            BOOL pretty = [_router boolQuery: @"pretty"];
#endif
            if (pretty) {
                [_data release];
                _data = [_response.body.asPrettyJSON mutableCopy];
            }
        }
    }
}


- (void)connectionDidClose {
    _connection = nil;
    [_data release];
    _data = nil;
}


@end
