//
//  CBLURLEndpoint.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLURLEndpoint.h"
#import "CBLURLEndpoint+Internal.h"

NSString* const kCBLURLEndpointScheme = @"ws";
NSString* const kCBLURLEndpointTLSScheme = @"wss";

@implementation CBLURLEndpoint

@synthesize url=_url;

- (instancetype) initWithURL: (NSURL*)url {
    self = [super init];
    if (self) {
        if (!([url.scheme isEqualToString: kCBLURLEndpointScheme] ||
              [url.scheme isEqualToString: kCBLURLEndpointTLSScheme])) {
            [NSException raise: NSInvalidArgumentException
                        format: @"The URL parameter has an unsupported URL scheme (%@). The supported URL schemes are %@ and %@",
                                url.scheme, kCBLURLEndpointScheme, kCBLURLEndpointTLSScheme];
        }
        _url = url;
    }
    return self;
}


- (NSString*) description {
    return [NSString stringWithFormat: @"URL[%@]", _url];
}

@end
