//
//  DNSService.mm
//  TestDNSService
//
//  Created by Pasin Suriyentrakorn on 12/4/22.
//

#import "CBLDNSService.h"
#import <arpa/inet.h>
#import <dns_sd.h>
#import <netdb.h>

@interface AddressInfo ()
- (instancetype) initWithAddress: (const struct sockaddr*)addr string: (NSString*)addrstr port: (UInt16)port type: (IPType)type;
@end

@implementation AddressInfo {
    NSData* _addr;
}

@synthesize addrstr=_addrstr;
@synthesize type=_type;

- (instancetype) initWithAddress: (const struct sockaddr*)addr
                          string: (NSString*)addrstr
                            port: (UInt16)port
                            type: (IPType)type {
    self = [super init];
    if (self) {
        if (type == kIPv4) {
            const struct sockaddr_in *addr_in = (const struct sockaddr_in*)addr;
            struct sockaddr_in addr2 = {
                .sin_len    = sizeof(struct sockaddr_in),
                .sin_family = AF_INET,
                .sin_port   = htons(port),
                .sin_addr   = {htonl(addr_in->sin_addr.s_addr)} };
            _addr = [NSMutableData dataWithBytes: &addr2 length: sizeof(struct sockaddr_in)];
        } else {
            const struct sockaddr_in6* addrIn = reinterpret_cast<const struct sockaddr_in6*>(addr);
            _addr = [NSMutableData dataWithBytes: addrIn length: sizeof(struct sockaddr_in6)];
        }
        _addrstr = addrstr;
        _type = type;
    }
    return self;
}

- (const struct sockaddr*) addr {
    return (const struct sockaddr *)_addr.bytes;
}

- (NSString*) description {
    return [NSString stringWithFormat: @"[%@],isIPv4=%d, %@", _addrstr, _type == 0, _addr];
}

@end

#define kTimeoutInterval 10.0
#define kWaitingInterval 0.5

@implementation CBLDNSResolver {
    NSString* _host;
    uint32_t _interface;
    id<DNSServiceDelegate> _delegate;
    
    DNSServiceRef _dnsServiceRef;
    dispatch_queue_t _dnsQueue;
    
    AddressInfo* _ipV4;
    DNSServiceErrorType _ipV4err;
    
    AddressInfo* _ipV6;
    DNSServiceErrorType _ipV6err;
    
    NSTimer* _timeoutTimer;
    NSTimer* _waitTimer;
    
    UInt16 _port;
}

- (instancetype) initWithHost: (NSString*)host interface: (uint32_t)interface port: (UInt16)port delegate: (id<DNSServiceDelegate>)delegate {
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
        
        _ipV4 = nil;
        _ipV4err = kDNSServiceErr_NoError;
        
        _ipV6 = nil;
        _ipV6err = kDNSServiceErr_NoError;
        
        NSLog(@"Resolving %@ ...", _host);
        
        const char* cHost = [_host cStringUsingEncoding: NSUTF8StringEncoding];
        DNSServiceFlags flags = kDNSServiceFlagsReturnIntermediates | kDNSServiceFlagsTimeout;
        DNSServiceProtocol protocol = kDNSServiceProtocol_IPv4 | kDNSServiceProtocol_IPv6;
        DNSServiceErrorType result = DNSServiceGetAddrInfo(&_dnsServiceRef, flags, _interface, protocol,
                                                           cHost, getAddrInfoCallback, (__bridge void*)self);
        
        if (result == kDNSServiceErr_NoError) {
            result = DNSServiceSetDispatchQueue(_dnsServiceRef, _dnsQueue);
        }
        
        if (result != kDNSServiceErr_NoError) {
            [self notifyError: result];
        }
        
        [_timeoutTimer invalidate];
        _timeoutTimer = [NSTimer scheduledTimerWithTimeInterval: kTimeoutInterval
                                                        repeats: NO
                                                          block: ^(NSTimer * _Nonnull timer) {
            @synchronized (self) {
                [self notifyError: kDNSServiceErr_Timeout];
            }
        }];
    }
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
    CBLDNSResolver* resolver = (__bridge CBLDNSResolver*)context;
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
        
        BOOL moreComing = flags & kDNSServiceFlagsMoreComing;
        
        if (errorCode != kDNSServiceErr_NoError) {
            if (address->sa_family != AF_INET && address->sa_family != AF_INET6 && !moreComing) {
                NSLog(@"DNS Service Error : %d", errorCode);
                [self notifyError: errorCode];
                return;
            }
            
            if (address->sa_family == AF_INET && !_ipV4) {
                _ipV4err = errorCode;
                NSLog(@"IPv4 Error : %d", errorCode);
            } else if (!_ipV6) {
                _ipV6err = errorCode;
                NSLog(@"IPv6 Error : %d", errorCode);
            }
            
            if (!moreComing) {
                [self checkResult];
            }
            return;
        }
        
        if (address->sa_family != AF_INET && address->sa_family != AF_INET6) {
            NSLog(@"Skip : Address is not either ipv4 or ipv6");
            return;
        }
        
        BOOL isValid = flags & kDNSServiceFlagsAdd;
        if (!isValid) {
            NSLog(@"Skip : Address is not valid");
            return;
        }
        
        NSString* addrstr = [self addrstr: address];
        IPType type = address->sa_family == AF_INET ? kIPv4 : kIPv6;
        AddressInfo* info = [[AddressInfo alloc] initWithAddress: address string: addrstr port: _port type: type];
        if (type == kIPv4) {
            _ipV4 = info;
            _ipV4err = kDNSServiceErr_NoError;
        } else {
            _ipV6 = info;
            _ipV6err = kDNSServiceErr_NoError;
        }
        
        NSLog(@"Found Address : %@", addrstr);
        NSLog(@"  IP Type : %@", type == kIPv4 ? @"IPv4" : @"IPv6");
        NSLog(@"  More Coming? : %@", moreComing ? @"YES" : @"NO");
        
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
            // Wait for 500ms to see if there is ipv4 address coming:
            if (!_waitTimer) {
                _waitTimer = [NSTimer scheduledTimerWithTimeInterval: kWaitingInterval
                                                             repeats: false
                                                               block: ^(NSTimer *timer) {
                    @synchronized (self) {
                        [self notifyResult];
                    }
                }];
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
        
        [_waitTimer invalidate];
        _waitTimer = nil;
        
        [_timeoutTimer invalidate];
        _timeoutTimer = nil;
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

- (void) notifyResult {
    if (!_dnsServiceRef) {
        return;
    }
    
    AddressInfo* info = _ipV4 ? _ipV4 : _ipV6;
    if (!info) {
        [self notifyError: kDNSServiceErr_NoSuchRecord];
        return;
    }
    
    NSLog(@"Notify Result : %@", info.addrstr);
    [_delegate didResolveSuccessWithAddress: info];
    [self stop];
}

- (void) notifyError: (DNSServiceErrorType)errorCode {
    if (!_dnsServiceRef) {
        return;
    }
    
    NSString* msg = [NSString stringWithFormat: @"Failed to resolve address for %@ via interface %d",
                     _host, _interface];
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
