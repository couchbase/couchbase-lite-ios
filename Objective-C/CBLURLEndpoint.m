//
//  CBLURLEndpoint.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/9/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLURLEndpoint.h"

@implementation CBLURLEndpoint

@synthesize host=_host, port=_port, path=_path, secure=_secure;

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

@end
