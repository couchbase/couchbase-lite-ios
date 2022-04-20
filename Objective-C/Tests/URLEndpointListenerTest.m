//
//  URLEndpointListenerTest.m
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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

#import "URLEndpointListenerTest.h"
#import "CBLTLSIdentity+Internal.h"
#import "CollectionUtils.h"

@implementation CBLURLEndpointListener (Test)

- (NSURL*) localURL {
    assert(self.port > 0);
    NSURLComponents* comps = [[NSURLComponents alloc] init];
    comps.scheme = self.config.disableTLS ? @"ws" : @"wss";
    comps.host = @"localhost";
    comps.port = @(self.port);
    comps.path = $sprintf(@"/%@",self.config.database.name);
    return comps.URL;
}

- (CBLURLEndpoint*) localEndpoint {
    return [[CBLURLEndpoint alloc] initWithURL: self.localURL];
}

@end

@implementation URLEndpointListenerTest

@synthesize localURL=_localURL, localEndpoint=_localEndpoint;

#pragma mark - Helper methods

- (Listener*) listenWithTLS: (BOOL)tls auth: (id<CBLListenerAuthenticator>)auth {
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    // Listener:
    Config* config = [[Config alloc] initWithDatabase: self.otherDB];
    config.port = tls ? kWssPort : kWsPort;
    config.disableTLS = !tls;
    config.authenticator = auth;
    
    return [self listen: config errorCode: 0 errorDomain: nil];
}

- (Listener*) listen: (Config*)config errorCode: (NSInteger)code errorDomain: (nullable NSString*)domain  {
    // Stop:
    if (_listener) {
        [_listener stop];
    }
    
    _listener = [[Listener alloc] initWithConfig: config];
    
    // Start:
    NSError* err = nil;
    BOOL success = [_listener startWithError: &err];
    Assert(success == (code == 0));
    if (code != 0) {
        AssertEqual(err.code, code);
        if (domain)
            AssertEqualObjects(err.domain, domain);
    } else
        AssertNil(err);
    
    return _listener;
}

- (void) stopListen {
    if (_listener) {
        [self stopListener: _listener];
    }
    _listener = nil;
}

- (void) stopListener: (CBLURLEndpointListener*)listener {
    CBLTLSIdentity* identity = listener.tlsIdentity;
    [listener stop];
    if (identity && self.keyChainAccessAllowed) {
        [self deleteFromKeyChain: identity];
    }
}

- (void) deleteFromKeyChain: (CBLTLSIdentity*)identity {
    [self ignoreException:^{
        NSError* error;
        Assert([identity deleteFromKeyChainWithError: &error],
               @"Couldn't delete identity: %@", error);
    }];
}

- (void) setUp {
    [super setUp];
}

- (void) tearDown {
    [super tearDown];
}

@end
