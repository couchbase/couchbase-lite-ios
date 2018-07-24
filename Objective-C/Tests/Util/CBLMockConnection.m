//
//  CBLMockConnection.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLMockConnection.h"
#import "CBLProtocolType.h"
#import "CBLMessageEndpointConnection.h"
#import "CBLMockConnectionErrorLogic.h"
#import "CBLMessage.h"
#import "CBLMessageEndpoint.h"
#import "CollectionUtils.h"
#import "CBLMessageEndpointListener.h"

@implementation CBLMockConnection
{
    @protected
    id<CBLReplicatorConnection> _connection;
    CBLProtocolType _protocolType;
    BOOL _noCloseRequest;
    CBLMessageEndpointListener* _host;
    dispatch_queue_t _dispatchQueue;
    
}
@synthesize errorLogic=_errorLogic;

- (id<CBLMockConnectionErrorLogic>) errorLogic {
    if(!_errorLogic) {
        _errorLogic = [CBLNoErrorLogic new];
    }
    return _errorLogic;
}

- (BOOL) isClient {
    return !_host;
}

- (instancetype) initWithListener: (CBLMessageEndpointListener*)listener
                      andProtocol: (CBLProtocolType)protocolType
{
    self = [super init];
    if(self) {
        _protocolType = protocolType;
        _host = listener;
        _dispatchQueue = dispatch_queue_create("CBLMockConnection", DISPATCH_QUEUE_SERIAL);
    }
    
    return self;
}

- (void) acceptBytes: (NSData *)message {
    dispatch_async(_dispatchQueue, ^{
        if(self.isClient && [self.errorLogic shouldCloseAtLocation: kCBLMockConnectionReceive]) {
            CBLMessagingError* error = [self.errorLogic createError];
            id<CBLReplicatorConnection> connection = _connection;
            _connection = nil; // Prevent any new bytes accepted
            [self connectionBroken: error];
            [connection close: error];
        } else {
            [_connection receive: [CBLMessage fromData: message]];
        }
    });
}

- (void) connectionBroken: (CBLMessagingError*)error {
    // should be overriden
}

- (void) performWrite: (NSData*)data {
    // should be overriden
}

- (void) open: (id<CBLReplicatorConnection>)connection
   completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    dispatch_async(_dispatchQueue, ^{
        _noCloseRequest = NO;
        _connection = connection;
        if(self.isClient && [_errorLogic shouldCloseAtLocation: kCBLMockConnectionConnect]) {
            CBLMessagingError* error = [_errorLogic createError];
            [self connectionBroken: error];
            completion(NO, error);
        } else {
            completion(YES, nil);
        }
    });
}

- (void) send: (CBLMessage*)message
   completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    dispatch_async(_dispatchQueue, ^{
        if(self.isClient && [_errorLogic shouldCloseAtLocation: kCBLMockConnectionSend]) {
            CBLMessagingError* error = [_errorLogic createError];
            [self connectionBroken: error];
            completion(NO, error);
        } else {
            [self performWrite: [message toData]];
            completion(YES, nil);
        }
    });
}

- (void) close:(NSError *)error completion:(void (^)(void))completion {
    dispatch_async(_dispatchQueue, ^{
        completion();
    });
}

@end

@implementation CBLMockClientConnection
{
    CBLMockServerConnection* _server;
}

- (instancetype) initWithEndpoint: (CBLMessageEndpoint*)endpoint {
    self = [super initWithListener: nil andProtocol: endpoint.protocolType];
    if(self) {
        _server = $castIf(CBLMockServerConnection, endpoint.target);
    }
    return self;
}

- (void) open: (id<CBLReplicatorConnection>)connection completion: (void (^)(BOOL, CBLMessagingError * _Nullable))completion {
    [super open: connection completion: ^(BOOL success, CBLMessagingError * _Nullable e) {
        if(success) {
            [_server clientOpened: self];
        }
        completion(success, e);
    }];
}

- (void) close: (NSError*)error completion: (void (^)(void))completion {
    dispatch_async(_dispatchQueue, ^{
        if(!_connection) {
            completion();
            return;
        }
        _connection = nil;
        if(_protocolType == kCBLProtocolTypeMessageStream && !_noCloseRequest) {
            [self connectionBroken: nil];
        }
        completion();
    });
}

- (void) connectionBroken: (CBLMessagingError*)error {
    CBLMockServerConnection* server = _server;
    _server = nil;
    [server clientDisconnected: error];
}

- (void) performWrite: (NSData*)data {
    [_server acceptBytes: data];
}

- (void) serverDisconnected {
    CBLMessagingError* error;
    if([self.errorLogic shouldCloseAtLocation: kCBLMockConnectionClose]) {
        error = [self.errorLogic createError];
    }
    _server = nil;
    _noCloseRequest = YES;
    [_connection close: error];
}

@end

@implementation CBLMockServerConnection
{
    CBLMockClientConnection* _client;
}

- (void) clientOpened: (CBLMockClientConnection*)client {
    _client = client;
    [_host accept: self];
}

- (void) clientDisconnected: (CBLMessagingError*)error {
    _noCloseRequest = YES;
    [_connection close: error];
}

- (void)close: (NSError*)error completion: (void (^)(void))completion {
    dispatch_async(_dispatchQueue, ^{
        _connection = nil;
        if(_protocolType == kCBLProtocolTypeMessageStream && !error) {
            [_client serverDisconnected];
        }
        completion();
    });
}

- (void) performWrite: (NSData*)data {
    [_client acceptBytes: data];
}

@end
