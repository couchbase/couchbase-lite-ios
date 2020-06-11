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

@synthesize listener=_listener, replicatorConnection=_replicatorConnection, protocolType=_protocolType;

@synthesize errorLogic=_errorLogic;

- (void) setErrorLogic: (id<CBLMockConnectionErrorLogic>)errorLogic {
    @synchronized (self) {
        _errorLogic = errorLogic;
    }
}

- (id<CBLMockConnectionErrorLogic>) errorLogic {
    @synchronized (self) {
        if (!_errorLogic) {
            _errorLogic = [CBLNoErrorLogic new];
        }
        return _errorLogic;
    }
}

- (BOOL) isClient {
    return !_listener;
}

- (instancetype) initWithListener: (CBLMessageEndpointListener*)listener protocol: (CBLProtocolType)protocolType {
    self = [super init];
    if (self) {
        _listener = listener;
        _protocolType = protocolType;
    }
    return self;
}

- (void) acceptBytes: (NSData *)message {
    NSLog(@"%@: Receiving message ...", self);
    if(self.isClient && [self.errorLogic shouldCloseAtLocation: kCBLMockConnectionReceive]) {
        CBLMessagingError* error = [self.errorLogic createError];
        NSLog(@"%@: Receiving message failed with error : %@", self, error);
        [self connectionBroken: error];
    } else {
        NSLog(@"%@: Message received", self);
        [_replicatorConnection receive: [CBLMessage fromData: message]];
    }
}

// Should be overriden
- (void) connectionBroken: (CBLMessagingError*)error {
    assert(false);
}

// Should be overriden
- (void) performWrite: (NSData*)data {
    assert(false);
}

- (void) open: (id<CBLReplicatorConnection>)connection completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    NSLog(@"%@: Open connection ...", self);
    _replicatorConnection = connection;
    CBLMessagingError* error;
    if(self.isClient && [self.errorLogic shouldCloseAtLocation: kCBLMockConnectionConnect]) {
        error = [self.errorLogic createError];
        [self connectionBroken: error];
    }
    NSLog(@"%@: Complete open connection with error: %@", self, error);
    completion(!error, error);
}

- (void) send: (CBLMessage*)message completion: (void (^)(BOOL success, CBLMessagingError* _Nullable))completion {
    NSLog(@"%@: Sending message ...", self);
    CBLMessagingError* error;
    if(self.isClient && [self.errorLogic shouldCloseAtLocation: kCBLMockConnectionSend]) {
        error = [self.errorLogic createError];
        NSLog(@"%@: Send message failed with error : %@", self, error);
        [self connectionBroken: error];
    } else {
        [self performWrite: [message toData]];
        NSLog(@"%@: Send message completed", self);
    }
    NSLog(@"%@: Complete send message with error: %@", self, error);
    completion(!error, error);
}

- (void) close: (NSError*)error completion: (void (^)(void))completion {
    completion();
}

@end

@interface CBLMockClientConnection ()
@property (atomic, nullable) CBLMockServerConnection* server;
@property (atomic) BOOL isClosed;
@property (atomic) BOOL isConnectionBroken;
@end

@implementation CBLMockClientConnection

@synthesize server=_server, isClosed = _isClosed, isConnectionBroken=_isConnectionBroken;

- (instancetype) initWithEndpoint: (CBLMessageEndpoint*)endpoint {
    self = [super initWithListener: nil protocol: endpoint.protocolType];
    if(self) {
        self.server = (CBLMockServerConnection*)endpoint.target;
    }
    return self;
}

- (void) open: (id<CBLReplicatorConnection>)connection completion: (void (^)(BOOL, CBLMessagingError * _Nullable))completion {
    [super open: connection completion: ^(BOOL success, CBLMessagingError *_Nullable e) {
        if (success) {
            self.isClosed = NO;
            self.isConnectionBroken = NO;
            [self.server clientOpened: self];
        }
        completion(success, e);
    }];
}

- (void) close: (NSError*)error completion: (void (^)(void))completion {
    BOOL connectionBroken = self.isConnectionBroken;
    NSLog(@"%@: Closing the connection with error: %@ (connectionBroken = %d)", self, error, connectionBroken);
    self.isClosed = YES;
    if (!connectionBroken)
        [self.server clientDisconnected: nil];
    completion();
    self.server = nil;
}

- (void) connectionBroken: (CBLMessagingError*)error {
    NSLog(@"%@: Connection broken with error: %@", self, error);
    self.isConnectionBroken = YES;
    [self.server clientDisconnected: error];
    [self.replicatorConnection close: error];
}

- (void) performWrite: (NSData*)data {
    NSLog(@"%@: Perform write with data size = %lu bytes to server", self, (unsigned long)data.length);
    CBLMockServerConnection* server = self.server;
    [server acceptBytes: data];
}

- (void) serverDisconnected {
    NSLog(@"%@: Server disconnected", self);
    if (!self.isClosed && !self.isConnectionBroken) {
        CBLMessagingError* error;
        if([self.errorLogic shouldCloseAtLocation: kCBLMockConnectionClose]) {
            error = [self.errorLogic createError];
        }
        NSLog(@"%@: Tell replicator to close connection with error: %@", self, error);
        [self.replicatorConnection close: error];
    }
}

@end

@interface CBLMockServerConnection ()
@property (atomic, nullable) CBLMockClientConnection* client;
@property (atomic) BOOL isClosed;
@end

@implementation CBLMockServerConnection

@synthesize client=_client, isClosed=_isClosed;

- (void) clientOpened: (CBLMockClientConnection*)client {
    NSLog(@"%@: client opened connection: %@", self, client);
    self.client = client;
    self.isClosed = NO;
    [self.listener accept: self];
}

- (void) clientDisconnected: (CBLMessagingError*)error {
    NSLog(@"%@: Client Disconnected with error: %@", self, error);
    if (!self.isClosed) {
        NSLog(@"%@: Tell replicator to close connection with error: %@", self, error);
        [self.replicatorConnection close: error];
    }
}

- (void) close: (NSError*)error completion: (void (^)(void))completion {
    NSLog(@"%@: Closing the connection with error: %@", self, error);
    self.isClosed = YES;
    [self.client serverDisconnected];
    completion();
    self.client = nil;
}

- (void) performWrite: (NSData*)data {
    NSLog(@"%@: Perform write with data size = %lu bytes to client", self, (unsigned long)data.length);
    [self.client acceptBytes: data];
    
}

@end
