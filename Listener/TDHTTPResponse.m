//
//  TDHTTPResponse.m
//  TouchDB
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "TDHTTPResponse.h"
#import "TDRouter.h"
#import "TDBody.h"


@implementation TDHTTPResponse


- (id) initWithTDResponse: (TDResponse*)response pretty: (BOOL)pretty {
    self = [super initWithData: (pretty ? response.body.asPrettyJSON : response.body.asJSON)];
    if (self) {
        _response = [response retain];
    }
    return self;
}

- (void)dealloc {
    [_response release];
    [super dealloc];
}

- (NSInteger)status {
    return _response.status;
}

- (NSDictionary *)httpHeaders {
    return _response.headers;
}


@end
