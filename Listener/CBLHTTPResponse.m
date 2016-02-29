//
//  CBLHTTPResponse.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLHTTPResponse.h"
#import "CBLHTTPConnection.h"
#import "CBLListener+Internal.h"
#import "CBL_Router.h"
#import "CBL_Body.h"

#define LogVerbose MYLogVerbose


// Declared here just so we can name them with @selector() without a compiler warning:
@interface CBL_Router (SomeActions)
- (CBLStatus) do_POST_all_docs: (CBLDatabase*)db;
- (CBLStatus) do_POST_changes: (CBLDatabase*)db;
- (CBLStatus) do_POST_revs_diff: (CBLDatabase*)db;
@end


@implementation CBLHTTPResponse
{
    CBL_Router* _router;
    CBLHTTPConnection* _connection;
    CBLResponse* _response;
    BOOL _finished;
    BOOL _askedIfChunked;
    BOOL _chunked;
    BOOL _delayedHeaders;
    NSData* _data;              // Data received, waiting to be read by the connection
    BOOL _dataMutable;          // Is _data an NSMutableData?
    UInt64 _dataOffset;         // Offset in response of 1st byte of _data
    UInt64 _offset;             // Offset in response for next readData
}


- (instancetype) initWithRouter: (CBL_Router*)router forConnection:(CBLHTTPConnection*)connection {
    self = [super init];
    if (self) {
        //EnableLog(YES);
        //EnableLogVerbose(Listener, YES);
        _router = router;
        _connection = connection;
        router.onResponseReady = ^(CBLResponse* r) {
            [self onResponseReady: r];
        };
        router.onDataAvailable = ^(NSData* data, BOOL finished) {
            [self onDataAvailable: data finished: finished];
        };
        router.onFinished = ^{
            [self onFinished];
        };

        if (connection.listener.readOnly) {
            NSString* method = router.request.HTTPMethod;
            router.onAccessCheck = ^CBLStatus(CBLDatabase* db, NSString* docID, SEL action) {
                if ([method isEqualToString: @"GET"] || [method isEqualToString: @"HEAD"]) {
                    return kCBLStatusOK;
                } else if ([method isEqualToString: @"PUT"] && [docID hasPrefix: @"_local/"]) {
                    // Allow read-only clients to save checkpoints:
                    return kCBLStatusOK;
                } else if ([method isEqualToString: @"POST"]) {
                    // POSTs that are legal read-only because they don't change anything:
                    if (action == @selector(do_POST_all_docs:)
                            || action == @selector(do_POST_changes:)
                            || action == @selector(do_POST_revs_diff:))
                        return kCBLStatusOK;
                }
                return kCBLStatusForbidden;
            };
        }
        
        // Run the router, asynchronously:
        LogVerbose(Listener, @"%@: Starting...", self);
        [router start];
        LogVerbose(Listener, @"%@: Returning from -init", self);
    }
    return self;
}

#if 0
- (void)dealloc {
    LogVerbose(Listener, @"DEALLOC %@", self);
}
#endif


- (NSString*) description {
    return [NSString stringWithFormat: @"Response[%@ %@]",
                                        _router.request.HTTPMethod, _router.request.URL.path];
}


// Note -- the method comments below are copied from the superclass header HTTPResponse.h.


/**
 * If you don't know the content-length in advance,
 * implement this method in your custom response class and return YES.
 **/
- (BOOL) isChunked {
    @synchronized(self) {
        if (!_askedIfChunked) {
            _chunked = !_finished;
        }
        LogVerbose(Listener, @"%@ answers isChunked=%d", self, _chunked);
        return _chunked;
    }
}


/**
 * If you need time to calculate any part of the HTTP response headers (status code or header fields),
 * this method allows you to delay sending the headers so that you may asynchronously execute the calculations.
 * Simply implement this method and return YES until you have everything you need concerning the headers.
 **/
- (BOOL) delayResponseHeaders {
    @synchronized(self) {
        LogVerbose(Listener, @"%@ answers delayResponseHeaders=%d", self, !_response);
        if (!_response)
            _delayedHeaders = YES;
        return !_response;
    }
}


- (void) onResponseReady: (CBLResponse*)response {
    @synchronized(self) {
        _response = response;
        LogTo(Listener, @"    %@ --> %i", self, _response.status);
        if (_delayedHeaders)
            [_connection responseHasAvailableData: self];
    }
}


/**
 * Status code for response.
 * Allows for responses such as redirect (301), etc.
**/
- (NSInteger) status {
    LogVerbose(Listener, @"%@ answers status=%d", self, _response.status);
    return _response.status;
}

/**
 * If you want to add any extra HTTP headers to the response,
 * simply return them in a dictionary in this method.
**/
- (NSDictionary *) httpHeaders {
    LogVerbose(Listener, @"%@ answers httpHeaders={%u headers}", self, (unsigned)_response.headers.count);
    return _response.headers;
}


- (void) onDataAvailable: (NSData*)data finished: (BOOL)finished {
    @synchronized(self) {
        LogVerbose(Listener, @"%@ adding %u bytes", self, (unsigned)data.length);
        if (!_data) {
            _data = [data copy];
            _dataMutable = NO;
        } else {
            if (!_dataMutable) {
                _data = [_data mutableCopy];
                _dataMutable = YES;
            }
            [(NSMutableData*)_data appendData: data];
        }
        if (finished)
            [self onFinished];
        else if (_chunked)
            [_connection responseHasAvailableData: self];
    }
}


/**
 * The HTTP server supports range requests in order to allow things like
 * file download resumption and optimized streaming on mobile devices.
**/
@synthesize offset=_offset;


/**
 * Returns the length of the data in bytes.
 * If you don't know the length in advance, implement the isChunked method and have it return YES.
**/
- (UInt64) contentLength {
    @synchronized(self) {
        if (!_finished)
            return 0;
        return _dataOffset + _data.length;
    }
}


/**
 * Returns the data for the response.
 * You do not have to return data of the exact length that is given.
 * You may optionally return data of a lesser length.
 * However, you must never return data of a greater length than requested.
**/
- (NSData*) readDataOfLength: (NSUInteger)length {
    @synchronized(self) {
        NSAssert(_offset >= _dataOffset, @"Invalid offset %llu, min is %llu", _offset, _dataOffset);
        NSRange range;
        range.location = (NSUInteger)(_offset - _dataOffset);
        if (range.location >= _data.length) {
            LogVerbose(Listener, @"%@ sending nil bytes", self);
            return nil;
        }
        NSUInteger bytesAvailable = _data.length - range.location;
        range.length = MIN(length, bytesAvailable);
        NSData* result = [_data subdataWithRange: range];
        _offset += range.length;
        LogVerbose(Listener, @"%@ sending %lu bytes (of %ld requested)",
              self, (unsigned long)result.length, (unsigned long)length);
        return result;
    }
}


/**
 * Should only return YES after the HTTPConnection has read all available data.
 * That is, all data for the response has been returned to the HTTPConnection via the readDataOfLength method.
**/
- (BOOL) isDone {
    LogVerbose(Listener, @"%@ answers isDone=%d", self, _finished);
    return _finished && (_offset >= _dataOffset + _data.length);
}


- (void) cleanUp {
    // Break cycles:
    _router.onResponseReady = nil;
    _router.onDataAvailable = nil;
    _router.onFinished = nil;
    if (!_finished) {
        _finished = true;
    }
}


- (void) onFinished {
    @synchronized(self) {
        if (_finished)
            return;
        _askedIfChunked = true;
        [self cleanUp];

        LogVerbose(Listener, @"%@ Finished!", self);

        if ((!_chunked || _offset == 0) && ![_router.request.HTTPMethod isEqualToString: @"HEAD"]) {
            // Response finished immediately, before the connection asked for any data, so we're free
            // to massage the response:
#if DEBUG
            BOOL pretty = YES;
#else
            BOOL pretty = [_router boolQuery: @"pretty"];
#endif
            if (pretty) {
                NSString* contentType = (_response.headers)[@"Content-Type"];
                if ([contentType hasPrefix: @"application/json"] && _data.length < 100000) {
                    LogVerbose(Listener, @"%@ prettifying response body", self);
                    _data = [_response.body.asPrettyJSON mutableCopy];
                }
            }
        }
        [_connection responseHasAvailableData: self];
    }
}


/**
 * This method is called from the HTTPConnection class when the connection is closed,
 * or when the connection is finished with the response.
 * If your response is asynchronous, you should implement this method so you know not to
 * invoke any methods on the HTTPConnection after this method is called (as the connection may be deallocated).
**/
- (void)connectionDidClose {
    @synchronized(self) {
        _connection = nil;
        _data = nil;
        [self cleanUp];
    }
}


@end
