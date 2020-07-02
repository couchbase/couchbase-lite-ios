//
//  CBLMockConnection.h
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

#import "CBLMessageEndpointConnection.h"
#import "CBLProtocolType.h"
@protocol CBLMockConnectionErrorLogic;
@class CBLMessageEndpointListener;
@class CBLMockServerConnection;

NS_ASSUME_NONNULL_BEGIN

@interface CBLMockConnection : NSObject <CBLMessageEndpointConnection>

@property (atomic, readonly, nullable) CBLMessageEndpointListener* listener;

@property (atomic, readonly, nullable) id<CBLReplicatorConnection> replicatorConnection;

@property (atomic, readonly) CBLProtocolType protocolType;

@property (atomic, readonly) BOOL isClient;

@property (atomic, nullable) id<CBLMockConnectionErrorLogic> errorLogic;

- (instancetype) initWithListener: (nullable CBLMessageEndpointListener*)listener protocol: (CBLProtocolType)protocolType;

- (void) acceptBytes: (NSData*)message;

- (void) connectionBroken: (nullable CBLMessagingError*)error;

- (void) performWrite: (NSData*)data;

@end

@interface CBLMockClientConnection : CBLMockConnection

- (instancetype) initWithEndpoint: (CBLMessageEndpoint*)endpoint;

- (void) serverConnected;

- (void) serverDisconnected;

@end

@interface CBLMockServerConnection : CBLMockConnection

- (void) clientConnected: (CBLMockClientConnection*)client;

- (void) clientDisconnected: (nullable CBLMessagingError*)error;

@end

NS_ASSUME_NONNULL_END
