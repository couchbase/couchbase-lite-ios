//
//  CBLDNSService.mm
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

#import "CBLDNSService.h"
#import <arpa/inet.h>
#import <dns_sd.h>
#import <netdb.h>

@interface AddressInfo ()
- (instancetype) initWithAddress: (const struct sockaddr*)addr
                         addrstr: (NSString*)addrstr
                            type: (IPType)type
                            host: (NSString*)host
                            port: (UInt16)port
                       interface: (UInt32)interface;
@end

@implementation AddressInfo {
    NSData* _addr;
}

@synthesize addrstr=_addrstr;
@synthesize type=_type;

@synthesize host=_host;
@synthesize port=_port;
@synthesize interface=_interface;

- (instancetype) initWithAddress: (const struct sockaddr*)addr
                         addrstr: (NSString*)addrstr
                            type: (IPType)type
                            host: (NSString*)host
                            port: (UInt16)port
                       interface: (UInt32)interface {
    self = [super init];
    if (self) {
        if (self) {
            struct sockaddr* mAddr = const_cast<struct sockaddr*>(addr);
            if (type == kIPv4) {
                struct sockaddr_in* addrIn = reinterpret_cast<struct sockaddr_in*>(mAddr);
                addrIn->sin_port = htons(port);
                _addr = [NSMutableData dataWithBytes: addrIn length: sizeof(struct sockaddr_in)];
            } else {
                struct sockaddr_in6* addrIn = reinterpret_cast<struct sockaddr_in6*>(mAddr);
                addrIn->sin6_port = htons(port);
                _addr = [NSMutableData dataWithBytes: addrIn length: sizeof(struct sockaddr_in6)];
            }
            _addrstr = addrstr;
            _type = type;
            _host = host;
            _port = port;
            _interface = interface;
        }
    }
    return self;
}

- (const struct sockaddr*) addr {
    return (const struct sockaddr *)_addr.bytes;
}

- (const struct sockaddr_in*) addrIn {
    return reinterpret_cast<const struct sockaddr_in*>(self.addr);
}

- (const struct sockaddr_in6*) addrIn6 {
    return reinterpret_cast<const struct sockaddr_in6*>(self.addr);
}

- (socklen_t) length {
    return _type == kIPv4 ? sizeof(*self.addrIn) : sizeof(*self.addrIn6);
}

- (NSString*) description {
    return [NSString stringWithFormat: @"%@ (%@, %d, %d, %lu)",
            _addrstr, _host, _port, (unsigned int)_interface, (unsigned long)_type];
}

@end

#define kTimeoutInterval 10.0
#define kWaitingInterval 2.0

@implementation CBLDNSService {
    NSString* _host;
    UInt32 _interface;
    id<DNSServiceDelegate> _delegate;
    
    DNSServiceRef _dnsServiceRef;
    dispatch_queue_t _dnsQueue;
    
    AddressInfo* _ipV4;
    DNSServiceErrorType _ipV4err;
    
    AddressInfo* _ipV6;
    DNSServiceErrorType _ipV6err;
    
    dispatch_block_t _timeoutBlock;
    dispatch_block_t _waitingBlock;
    
    UInt16 _port;
}

- (instancetype) initWithHost: (NSString*)host
                    interface: (UInt32)interface
                         port: (UInt16)port
                     delegate: (id<DNSServiceDelegate>)delegate {
    self = [super init];
    if (self) {
        _host = host;
        _port = port;
        _interface = interface;
        _delegate = delegate;
        
        _dnsServiceRef = NULL;
        _dnsQueue = dispatch_queue_create(@"DNSService".UTF8String, DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void) start {
    @synchronized (self) {
        if (_dnsServiceRef)
            return;
        
        if ([self checkAlreadyIPAddress])
            return;
        
        _ipV4 = nil;
        _ipV4err = kDNSServiceErr_NoError;
        
        _ipV6 = nil;
        _ipV6err = kDNSServiceErr_NoError;
        
        CBLLogVerbose(WebSocket, @"%@: Looking up '%@' on interface index '%d'", self, _host, (unsigned int)_interface);
        
        const char* cHost = [_host cStringUsingEncoding: NSUTF8StringEncoding];
        DNSServiceFlags flags = kDNSServiceFlagsReturnIntermediates;
        DNSServiceProtocol protocol = kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6;
        DNSServiceErrorType result = DNSServiceGetAddrInfo(&_dnsServiceRef, flags, _interface, protocol,
                                                           cHost, getAddrInfoCallback, (__bridge void*)self);
        
        if (result == kDNSServiceErr_NoError) {
            result = DNSServiceSetDispatchQueue(_dnsServiceRef, _dnsQueue);
        }
        
        if (result != kDNSServiceErr_NoError) {
            dispatch_async(_dnsQueue, ^{
                [self notifyError: result];
            });
            return;
        }
        
        if (!_timeoutBlock) {
            _timeoutBlock = dispatch_block_create(DISPATCH_BLOCK_ASSIGN_CURRENT, ^{
                @synchronized (self) {
                    CBLWarnError(WebSocket, @"%@: Looking up '%@' timeout", self, self->_host);
                    [self notifyError: kDNSServiceErr_Timeout];
                }
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeoutInterval * NSEC_PER_SEC)),
                           _dnsQueue, _timeoutBlock);
        }
    }
}

- (BOOL) checkAlreadyIPAddress {
    AddressInfo* info;
    
    const char* cHost = [_host cStringUsingEncoding: NSUTF8StringEncoding];
    
    struct sockaddr_in addrV4;
    if (inet_pton(AF_INET, cHost, &addrV4.sin_addr) == 1) {
        addrV4.sin_family = AF_INET;
        info = [[AddressInfo alloc] initWithAddress: (const struct sockaddr*)&addrV4
                                            addrstr: _host
                                               type: kIPv4
                                               host: _host
                                               port: _port
                                          interface: _interface];
    }

    if (!info) {
        struct sockaddr_in6 addrV6;
        if (inet_pton(AF_INET6, cHost, &addrV6.sin6_addr) == 1) {
            addrV6.sin6_family = AF_INET6;
            info = [[AddressInfo alloc] initWithAddress: (const struct sockaddr*)&addrV6
                                                addrstr: _host
                                                   type: kIPv6
                                                   host: _host
                                                   port: _port
                                              interface: _interface];
        }
    }
    
    if (info) {
        dispatch_async(_dnsQueue, ^{
            [self->_delegate didResolveSuccessWithAddress: info];
        });
        return true;
    }
    return false;
}

static void getAddrInfoCallback(DNSServiceRef sdref,
                                const DNSServiceFlags flags,
                                uint32_t interfaceIndex,
                                DNSServiceErrorType errorCode,
                                const char *hostname,
                                const struct sockaddr *address,
                                uint32_t ttl,
                                void *context)
{
    CBLDNSService* resolver = (__bridge CBLDNSService*)context;
    [resolver didResolveAddressWithDNSService: sdref address: address flags: flags error: errorCode];
}

- (void) didResolveAddressWithDNSService: (DNSServiceRef)ref
                                 address: (const struct sockaddr *)address
                                   flags: (const DNSServiceFlags)flags
                                   error: (DNSServiceErrorType)errorCode {
    @synchronized (self) {
        if (ref != _dnsServiceRef) {
            return; // Already stopped
        }
        
        BOOL moreComing = (flags & kDNSServiceFlagsMoreComing) == kDNSServiceFlagsMoreComing;
        
        if (errorCode != kDNSServiceErr_NoError) {
            if (address->sa_family != AF_INET && address->sa_family != AF_INET6 && !moreComing) {
                CBLLogVerbose(WebSocket, @"%@: Received error %@", self, [self errorInfo: errorCode]);
                [self notifyError: errorCode];
                return;
            }
            
            if (address->sa_family == AF_INET && !_ipV4) {
                _ipV4err = errorCode;
                CBLLogVerbose(WebSocket, @"%@: Received error %@ from querying IPv4 record",
                              self, [self errorInfo: errorCode]);
            } else if (!_ipV6) {
                _ipV6err = errorCode;
                CBLLogVerbose(WebSocket, @"%@: Received error %@ from querying IPv6 record",
                              self, [self errorInfo: errorCode]);
            }
            
            if (!moreComing) {
                [self checkResult];
            }
            return;
        }
        
        if (address->sa_family != AF_INET && address->sa_family != AF_INET6) {
            return;
        }
        
        BOOL isValid = (flags & kDNSServiceFlagsAdd) == kDNSServiceFlagsAdd;
        if (!isValid) {
            return;
        }
        
        NSString* addrstr = [self addrstr: address];
        IPType type = address->sa_family == AF_INET ? kIPv4 : kIPv6;
        AddressInfo* info = [[AddressInfo alloc] initWithAddress: address
                                                         addrstr: addrstr
                                                            type: type
                                                            host: _host
                                                            port: _port
                                                       interface: _interface];
        if (type == kIPv4) {
            _ipV4 = info;
            _ipV4err = kDNSServiceErr_NoError;
        } else {
            _ipV6 = info;
            _ipV6err = kDNSServiceErr_NoError;
        }
        
        CBLLogVerbose(WebSocket, @"%@: Found address : %@", self, addrstr);
        CBLLogVerbose(WebSocket, @"%@:   Type : %@", self, type == kIPv4 ? @"IPv4" : @"IPv6");
        CBLLogVerbose(WebSocket, @"%@:   More Coming? : %@", self, moreComing ? @"YES" : @"NO");
        
        if (!moreComing) {
            [self checkResult];
        }
    }
}

- (void) checkResult {
    if (_ipV4) {
        // Prefer IPv4
        [self notifyResult];
    } else if (_ipV6) {
        if (_ipV4err == kDNSServiceErr_NoSuchRecord) {
            [self notifyResult];
        } else {
            // Wait to see if there is ipv4 address coming:
            if (!_waitingBlock) {
                _waitingBlock = dispatch_block_create(DISPATCH_BLOCK_ASSIGN_CURRENT, ^{
                    @synchronized (self) {
                        [self notifyResult];
                    }
                });
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kWaitingInterval * NSEC_PER_SEC)),
                               _dnsQueue, _waitingBlock);
            }
        }
    } else {
        if (_ipV4err != kDNSServiceErr_NoError && _ipV6err != kDNSServiceErr_NoError) {
            [self notifyError: _ipV4err];
        }
    }
}

- (void) stop {
    @synchronized (self) {
        if (_dnsServiceRef) {
            DNSServiceRefDeallocate(_dnsServiceRef);
            _dnsServiceRef = NULL;
        }
        
        if (_waitingBlock) {
            dispatch_cancel(_waitingBlock);
            _waitingBlock = nil;
        }
        
        if (_timeoutBlock) {
            dispatch_cancel(_timeoutBlock);
            _timeoutBlock = nil;
        }
    }
}

- (NSString*) addrstr: (const struct sockaddr *)address {
    NSString* addrstr = @"Unknown";
    if (address->sa_family == AF_INET) {
        char addrBuf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((struct sockaddr_in*)address)->sin_addr, addrBuf, INET_ADDRSTRLEN) != NULL) {
            addrstr = [NSString stringWithUTF8String: addrBuf];
        }
    } else {
        char addrBuf[INET6_ADDRSTRLEN];
        if (inet_ntop(AF_INET6, &((struct sockaddr_in6*)address)->sin6_addr, addrBuf, INET6_ADDRSTRLEN) != NULL) {
            addrstr = [NSString stringWithUTF8String: addrBuf];
        }
    }
    return addrstr;
}

- (NSString*) errorInfo: (DNSServiceErrorType)errorCode {
    NSString* desc;
    if (errorCode == kDNSServiceErr_NoSuchRecord)
        desc = @"NoSuchRecord";
    
    if (desc)
        return [NSString stringWithFormat: @"%d (%@)", errorCode, desc];
    else
        return [NSString stringWithFormat: @"%d", errorCode];
}

- (void) notifyResult {
    if (!_dnsServiceRef) {
        return;
    }
    
    AddressInfo* info = _ipV4 ? _ipV4 : _ipV6;
    if (!info) {
        [self notifyError: kDNSServiceErr_NoSuchRecord];
        return;
    }
    
    [_delegate didResolveSuccessWithAddress: info];
    [self stop];
}

- (void) notifyError: (DNSServiceErrorType)errorCode {
    if (!_dnsServiceRef) {
        return;
    }
    
    NSString* msg = [NSString stringWithFormat: @"Failed to resolve address for %@ via interface %d",
                     _host, (unsigned int)_interface];
    NSError* error;
    if (errorCode == kDNSServiceErr_NoSuchRecord) {
        error = addrInfoError(EAI_NONAME, msg);
    } else {
        error = addrInfoError(EAI_FAIL, msg);
    }
    [_delegate didResolveFailWithError: error];
    [self stop];
}

static inline NSError* addrInfoError(int code, NSString* msg) {
    NSString* failure = [NSString stringWithFormat:@"%d", code];
    return [NSError errorWithDomain: (id)kCFErrorDomainCFNetwork
                               code: kCFHostErrorUnknown
                           userInfo: @{NSLocalizedDescriptionKey: msg,
                                       (id)kCFGetAddrInfoFailureKey: failure}];
}

@end
