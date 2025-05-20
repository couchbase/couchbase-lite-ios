//
//  CBLWebSocket.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>
#import "CBLCookieStore.h"

@class CBLWebSocket;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLWebSocketContext <NSObject>

- (nullable NSURL*) cookieURLForWebSocket: (CBLWebSocket*)websocket;

- (nullable id <CBLCookieStore>) cookieStoreForWebsocket: (CBLWebSocket*)websocket;

- (nullable NSString*) networkInterfaceForWebsocket: (CBLWebSocket*)websocket;

- (void) webSocket: (CBLWebSocket*)websocket didReceiveServerCert: (SecCertificateRef)cert;

@end

@interface CBLWebSocket : NSObject <NSURLSessionStreamDelegate>

+ (C4SocketFactory) socketFactory;

+ (nullable NSString*) webSocketAcceptHeaderForKey: (NSString*)key;

// For testing purpose only
+ (NSArray*) parseCookies: (NSString*) cookie;

// For testing purpose, we exposing this function
+ (nullable NSString*) getNetworkInterfaceName: (NSString*)name error: (NSError**)outError;

@end

NS_ASSUME_NONNULL_END
