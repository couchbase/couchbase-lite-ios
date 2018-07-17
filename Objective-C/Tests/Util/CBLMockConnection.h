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

@interface CBLMockConnection : NSObject <CBLMessageEndpointConnection>

@property (nonatomic) id<CBLMockConnectionErrorLogic> errorLogic;

@property (nonatomic, readonly) BOOL isClient;

- (instancetype)initWithListener:(CBLMessageEndpointListener*)listener andProtocol:(CBLProtocolType)protocolType;

- (void)acceptBytes:(NSData *)message;

- (void)connectionBroken:(CBLMessagingError *)error;

- (void)performWrite:(NSData *)data;

@end

@interface CBLMockClientConnection : CBLMockConnection

- (instancetype)initWithEndpoint:(CBLMessageEndpoint *)endpoint;

- (void)serverDisconnected;

@end

@interface CBLMockServerConnection : CBLMockConnection

- (void)clientOpened:(CBLMockClientConnection *)client;

- (void)clientDisconnected:(CBLMessagingError *)error;

@end
