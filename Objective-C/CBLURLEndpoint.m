//
//  CBLURLEndpoint.mm
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLURLEndpoint+Internal.h"

#define kCBLURLEndpointScheme @"ws"
#define kCBLURLEndpointTLSScheme @"wss"

@implementation CBLURLEndpoint

@synthesize host=_host, port=_port, path=_path, secure=_secure;
@synthesize url=_url;

- (instancetype) initWithHost: (NSString*)host secure: (BOOL)secure {
    return [self initWithHost: host port: -1 path: nil secure: false];
}


- (instancetype) initWithHost: (NSString*)host
                         path: (nullable NSString*)path
                       secure: (BOOL)secure
{
    return [self initWithHost: host port: -1 path: path secure: false];
}


- (instancetype) initWithHost: (NSString*)host
                         port: (NSInteger)port
                         path: (nullable NSString*)path
                       secure: (BOOL)secure
{
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _path = path;
        _secure = secure;
    }
    return self;
}


- (NSURL*) url {
    if (!_url) {
        NSURLComponents* comp = [NSURLComponents new];
        comp.scheme = _secure ? kCBLURLEndpointTLSScheme : kCBLURLEndpointScheme;
        comp.host = _host;
        if (_port >= 0)
            comp.port = @(_port);
        if (_path)
            comp.path = [_path hasPrefix: @"/"] ? _path : $sprintf(@"/%@", _path);
        _url = comp.URL;
    }
    return _url;
}

@end
