//
//  CBLHTTPResponse.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
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
#import "CBLListener.h"
#import "CBL_Router.h"
#import "CBL_Body.h"

#import "CBLBase64.h"
#import "CBLMisc.h"

#import "Logging.h"


@interface CBLHTTPResponse ()
- (void) onResponseReady: (CBLResponse*)response;
- (void) onDataAvailable: (NSData*)data finished: (BOOL)finished;
- (void) onFinished;
@end



@implementation CBLHTTPResponse


- (instancetype) initWithRouter: (CBL_Router*)router forConnection:(CBLHTTPConnection*)connection {
    self = [super init];
    if (self) {
        //EnableLog(YES);
        //EnableLogTo(CBLListenerVerbose, YES);
        _router = router;
        _connection = connection;
        
        // Check to see if there is an AuthSession cookie and authenticate the user if not timed out
        [_connection processAuthSession];

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
                if ([method isEqualToString: @"GET"] || [method isEqualToString: @"HEAD"])
                    return kCBLStatusOK;
                if ([method isEqualToString: @"POST"]) {
                    NSString* actionStr = NSStringFromSelector(action);
                    if ([actionStr isEqualToString: @"do_POST_all_docs:"]
                            || [actionStr isEqualToString: @"do_POST_revs_diff:"])
                        return kCBLStatusOK;
                }
                return kCBLStatusForbidden;
            };
        }
        
        // Run the router, asynchronously:
        LogTo(CBLListenerVerbose, @"%@: Starting...", self);
        [router start];
        LogTo(CBLListenerVerbose, @"%@: Returning from -init", self);
    }
    return self;
}

#if 0
- (void)dealloc {
    LogTo(CBLListenerVerbose, @"DEALLOC %@", self);
}
#endif


- (NSString*) description {
    return [NSString stringWithFormat: @"Response[%@ %@]",
                                        _router.request.HTTPMethod, _router.request.URL.path];
}


/**
 * If you don't know the content-length in advance,
 * implement this method in your custom response class and return YES.
 **/
- (BOOL) isChunked {
    @synchronized(self) {
        if (!_askedIfChunked) {
            _chunked = !_finished;
        }
        LogTo(CBLListenerVerbose, @"%@ answers isChunked=%d", self, _chunked);
        return _chunked;
    }
}


- (BOOL) delayResponseHeaders {
    @synchronized(self) {
        LogTo(CBLListenerVerbose, @"%@ answers delayResponseHeaders=%d", self, !_response);
        if (!_response)
            _delayedHeaders = YES;
        return !_response;
    }
}


- (void) onResponseReady: (CBLResponse*)response {
    @synchronized(self) {
        _response = response;
        LogTo(CBLListener, @"    %@ --> %i", self, _response.status);
        if (_delayedHeaders)
            [_connection responseHasAvailableData: self];
    }
}


- (NSInteger) status {
    LogTo(CBLListenerVerbose, @"%@ answers status=%d", self, _response.status);
    return _response.status;
}

- (NSDictionary *) httpHeaders {
    LogTo(CBLListenerVerbose, @"%@ answers httpHeaders={%u headers}", self, (unsigned)_response.headers.count);
    
    // If the session has been authenticated, write the AuthSession header
    [_connection writeAuthSession:_response];
    return _response.headers;
}


- (void) onDataAvailable: (NSData*)data finished: (BOOL)finished {
    @synchronized(self) {
        LogTo(CBLListenerVerbose, @"%@ adding %u bytes", self, (unsigned)data.length);
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


@synthesize offset=_offset;


- (UInt64) contentLength {
    @synchronized(self) {
        if (!_finished)
            return 0;
        return _dataOffset + _data.length;
    }
}


- (NSData*) readDataOfLength: (NSUInteger)length {
    @synchronized(self) {
        NSAssert(_offset >= _dataOffset, @"Invalid offset %llu, min is %llu", _offset, _dataOffset);
        NSRange range;
        range.location = (NSUInteger)(_offset - _dataOffset);
        if (range.location >= _data.length) {
            LogTo(CBLListenerVerbose, @"%@ sending nil bytes", self);
            return nil;
        }
        NSUInteger bytesAvailable = _data.length - range.location;
        range.length = MIN(length, bytesAvailable);
        NSData* result = [_data subdataWithRange: range];
        _offset += range.length;
        LogTo(CBLListenerVerbose, @"%@ sending %u bytes", self, (unsigned)result.length);
        return result;
    }
}


- (BOOL) isDone {
    LogTo(CBLListenerVerbose, @"%@ answers isDone=%d", self, _finished);
    return _finished;
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

        LogTo(CBLListenerVerbose, @"%@ Finished!", self);

        if ((!_chunked || _offset == 0) && ![_router.request.HTTPMethod isEqualToString: @"HEAD"]) {
            // Response finished immediately, before the connection asked for any data, so we're free
            // to massage the response:
            LogTo(CBLListenerVerbose, @"%@ prettifying response body", self);
#if DEBUG
            BOOL pretty = YES;
#else
            BOOL pretty = [_router boolQuery: @"pretty"];
#endif
            if (pretty) {
                NSString* contentType = (_response.headers)[@"Content-Type"];
                if ([contentType hasPrefix: @"application/json"] && _data.length < 100000) {
                    _data = [_response.body.asPrettyJSON mutableCopy];
                }
            }
        }
        [_connection responseHasAvailableData: self];
    }
}


- (void)connectionDidClose {
    @synchronized(self) {
        _connection = nil;
        _data = nil;
        [self cleanUp];
    }
}


@end
