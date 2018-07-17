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
}
@synthesize errorLogic=_errorLogic;

- (id<CBLMockConnectionErrorLogic>)errorLogic {
    if(!_errorLogic) {
        _errorLogic = [CBLNoErrorLogic new];
    }
    
    return _errorLogic;
}

- (BOOL)isClient {
    return !_host;
}

- (instancetype)initWithListener:(CBLMessageEndpointListener *)listener andProtocol:(CBLProtocolType)protocolType {
    self = [super init];
    if(self) {
        _protocolType = protocolType;
        _host = listener;
    }
    
    return self;
}

- (void)acceptBytes:(NSData *)message {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if(self.isClient && [self.errorLogic shouldCloseAtLocation:kCBLMockConnectionReceive]) {
            CBLMessagingError* error = [self.errorLogic createError];
            [self connectionBroken:error];
            [_connection close:error];
        } else {
            [_connection receive:[CBLMessage fromData:message]];
        }
    });
    
}

- (void)connectionBroken:(CBLMessagingError *)error {
    // should be overriden
}

- (void)performWrite:(NSData *)data {
    // should be overriden
}

- (void) open: (id<CBLReplicatorConnection>)connection
   completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    _noCloseRequest = NO;
    _connection = connection;
    if(self.isClient && [_errorLogic shouldCloseAtLocation:kCBLMockConnectionConnect]) {
        CBLMessagingError* error = [_errorLogic createError];
        [self connectionBroken:error];
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
             completion(NO, error);
         });
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completion(YES, nil);
        });
    }
}

- (void) send: (CBLMessage*)message
   completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    if(self.isClient && [_errorLogic shouldCloseAtLocation:kCBLMockConnectionSend]) {
        CBLMessagingError* error = [_errorLogic createError];
        [self connectionBroken:error];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completion(NO, error);
        });
    } else {
        [self performWrite:[message toData]];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completion(YES, nil);
        });
    }
}

- (void) close:(NSError *)error completion:(void (^)(void))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        completion();
    });
}

@end

@implementation CBLMockClientConnection
{
    CBLMockServerConnection* _server;
}

- (instancetype)initWithEndpoint:(CBLMessageEndpoint *)endpoint {
    self = [super initWithListener:nil andProtocol:endpoint.protocolType];
    if(self) {
        _server = $castIf(CBLMockServerConnection, endpoint.target);
    }
    
    return self;
}

- (void)connectionBroken:(CBLMessagingError *)error {
    CBLMockServerConnection* server = _server;
    _server = nil;
    [server clientDisconnected:error];
}

- (void)open:(id<CBLReplicatorConnection>)connection completion:(void (^)(BOOL, CBLMessagingError * _Nullable))completion {
    [super open:connection completion:^(BOOL success, CBLMessagingError * _Nullable e) {
        if(success) {
            [_server clientOpened:self];
        }
        
        completion(success, e);
    }];
}

- (void)close:(NSError *)error completion:(void (^)(void))completion {
    if(!_connection) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completion();
        });
        return;
    }
    
    if([self.errorLogic shouldCloseAtLocation:kCBLMockConnectionClose]) {
        CBLMessagingError* e = [self.errorLogic createError];
        [self connectionBroken:e];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completion(); // FIXME: How to report this error?
        });
        return;
    }
    
    _connection = nil;
    if(_protocolType == kCBLProtocolTypeMessageStream && !_noCloseRequest) {
        [self connectionBroken:nil];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        completion();
    });
}

- (void)serverDisconnected {
    _server = nil;
    _noCloseRequest = YES;
    [_connection close:nil];
}

- (void)performWrite:(NSData *)data {
    [_server acceptBytes:data];
}

@end

@implementation CBLMockServerConnection
{
    CBLMockClientConnection* _client;
}

- (void)clientOpened:(CBLMockClientConnection *)client {
    _client = client;
    [_host accept:self];
}

- (void)clientDisconnected:(CBLMessagingError *)error {
    _noCloseRequest = YES;
    [_connection close:error];
}

- (void)close:(NSError *)error completion:(void (^)(void))completion {
    [_host close:self];
    if(_protocolType == kCBLProtocolTypeMessageStream && !error && !_noCloseRequest) {
        [_client serverDisconnected];
    }
    
    completion();
}

- (void)performWrite:(NSData *)data {
    [_client acceptBytes:data];
}

@end
