//
//  CBLHTTPResponse.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "HTTPResponse.h"
@class CBLHTTPConnection, CBL_Router, CBLResponse;


@interface CBLHTTPResponse : NSObject <HTTPResponse>
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

- (instancetype) initWithRouter: (CBL_Router*)router forConnection:(CBLHTTPConnection*)connection;

@property UInt64 offset;

@end
