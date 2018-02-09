//
//  CBLURLEndpoint.mm
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
