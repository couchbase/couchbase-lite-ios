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
    NSData* responseBody = (pretty ? response.body.asPrettyJSON : response.body.asJSON);
    int status = response.status;
    if (!responseBody && status >= 300) {
        // Put a generic error message in the body:
        NSString* errorMsg;
        switch (status) {
            case 404:   errorMsg = @"not_found"; break;
            // TODO: There are more of these to add; see error_info() in couch_httpd.erl
            default:
                errorMsg = [NSHTTPURLResponse localizedStringForStatusCode: status];
        }
        responseBody = [[NSString stringWithFormat: @"{\"status\": %i, \"error\":\"%@\"}\n",
                                status, errorMsg]
                            dataUsingEncoding: NSUTF8StringEncoding];
        [response.headers setObject: @"text/plain; encoding=UTF-8" forKey: @"Content-Type"];
    }
    
    self = [super initWithData: responseBody];
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
