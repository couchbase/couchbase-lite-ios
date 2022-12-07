//
//  CBLDNSService.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, IPType) {
    kIPv4 = 0,
    kIPv6
};

@interface AddressInfo : NSObject

@property (nonatomic, readonly) const struct sockaddr* addr;
@property (nonatomic, readonly) const struct sockaddr_in* addrIn;
@property (nonatomic, readonly) const struct sockaddr_in6* addrIn6;

@property (nonatomic, readonly) NSString* addrstr;
@property (nonatomic, readonly) IPType type;

@property (nonatomic, readonly) NSString* host;
@property (nonatomic, readonly) UInt16 port;
@property (nonatomic, readonly) UInt32 interface;

@end

@protocol DNSServiceDelegate <NSObject>
- (void) didResolveSuccessWithAddress: (AddressInfo*)info;
- (void) didResolveFailWithError: (NSError*)error;
@end

@interface CBLDNSService : NSObject

- (instancetype) initWithHost: (NSString*)host
                    interface: (UInt32)interface
                         port: (UInt16)port
                     delegate: (id<DNSServiceDelegate>)delegate;
- (void) start;
- (void) stop;

@end

NS_ASSUME_NONNULL_END
