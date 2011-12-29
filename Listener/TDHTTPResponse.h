//
//  TDHTTPResponse.h
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "HTTPDataResponse.h"
@class TDResponse;

@interface TDHTTPResponse : HTTPDataResponse
{
    TDResponse* _response;
}

- (id) initWithTDResponse: (TDResponse*)response pretty: (BOOL)pretty;

- (NSInteger)status;
- (NSDictionary *)httpHeaders;

@end
