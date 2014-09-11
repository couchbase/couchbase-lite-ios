//
//  CBLListener.m
//  CouchbaseLiteListener
//
//  Created by Jens Alfke on 12/29/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLListener.h"
#import "CBLHTTPServer.h"
#import "CBLHTTPConnection.h"
#import "CouchbaseLitePrivate.h"
#import "CBL_Server.h"
#import "Logging.h"

#import "HTTPServer.h"
#import "HTTPLogging.h"

#import <sys/types.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <arpa/inet.h>


static NSArray* GetIPv4Addresses(void);


@interface CBL_MYDDLogger : DDAbstractLogger
@end


@implementation CBLListener
{
    CBLHTTPServer* _httpServer;
    CBL_Server* _tdServer;
    NSString* _realm;
    BOOL _readOnly;
    BOOL _requiresAuth;
    NSDictionary* _passwords;
    SecIdentityRef _SSLIdentity;
    NSArray* _SSLExtraCertificates;
}


+ (void) initialize {
    if (self == [CBLListener class]) {
        if (WillLogTo(CBLListener)) {
            [DDLog addLogger:[[CBL_MYDDLogger alloc] init]];
        }
    }
}


@synthesize readOnly=_readOnly, requiresAuth=_requiresAuth, realm=_realm,
            SSLExtraCertificates=_SSLExtraCertificates;


- (instancetype) initWithManager: (CBLManager*)manager port: (UInt16)port {
    self = [super init];
    if (self) {
        _tdServer = manager.backgroundServer;
        _httpServer = [[CBLHTTPServer alloc] init];
        _httpServer.listener = self;
        _httpServer.tdServer = _tdServer;
        _httpServer.port = port;
        _httpServer.connectionClass = [CBLHTTPConnection class];
        self.realm = @"CouchbaseLite";
    }
    return self;
}


- (void)dealloc
{
    [self stop];
    if (_SSLIdentity)
        CFRelease(_SSLIdentity);
}


- (void) setBonjourName: (NSString*)name type: (NSString*)type {
    _httpServer.name = name;
    _httpServer.type = type;
}

- (NSDictionary *)TXTRecordDictionary                   {return _httpServer.TXTRecordDictionary;}
- (void)setTXTRecordDictionary:(NSDictionary *)dict     {_httpServer.TXTRecordDictionary = dict;}



- (BOOL) start: (NSError**)outError {
    return [_httpServer start: outError];
}

- (void) stop {
    [_httpServer stop];
}


- (UInt16) port {
    return _httpServer.listeningPort;
}


- (NSURL*) URL {
    UInt16 port = self.port;
    NSArray* addresses = GetIPv4Addresses();
    if (port == 0 || addresses.count == 0)
        return nil;
    NSString* urlStr = [NSString stringWithFormat: @"http%@://%@:%d/",
                        (_SSLIdentity ? @"s" : @""), addresses[0], port];
    return [NSURL URLWithString: urlStr];
}


- (void) setPasswords: (NSDictionary*)passwords {
    _passwords = [passwords copy];
    _requiresAuth = (_passwords != nil);
}

- (NSString*) passwordForUser:(NSString *)username {
    return _passwords[username];
}


- (SecIdentityRef) SSLIdentity {
    return _SSLIdentity;
}

- (void) setSSLIdentity:(SecIdentityRef)identity {
    if (identity)
        CFRetain(identity);
    if (_SSLIdentity)
        CFRelease(_SSLIdentity);
    _SSLIdentity = identity;
}


@end



// Adapter to output DDLog messages (from CocoaHTTPServer) via MYUtilities logging.
@implementation CBL_MYDDLogger

- (void) logMessage:(DDLogMessage *)logMessage {
    Log(@"%@", logMessage->logMsg);
}

@end



static NSArray* GetIPv4Addresses(void) {
    // getifaddrs returns a linked list of interface entries;
    // find each active non-loopback interface whose name begins with "en" (an ugly hack
    // to identify WiFi or Ethernet as opposed to a cellular connection.)
    // IPv6 addresses are added, but at the end of the array to make them easier to skip
    // since for most purposes IPv4 addresses are still preferred.
    NSMutableArray* addresses = [NSMutableArray array];
    NSUInteger ipv4count = 0;
    struct ifaddrs *interfaces;
    if( getifaddrs(&interfaces) == 0 ) {
        struct ifaddrs *interface;
        for( interface=interfaces; interface; interface=interface->ifa_next ) {
            if( (interface->ifa_flags & IFF_UP) && ! (interface->ifa_flags & IFF_LOOPBACK)
               && (strncmp(interface->ifa_name, "en", 2) == 0)) {
                const struct sockaddr_in *addr = (const struct sockaddr_in*) interface->ifa_addr;
                if( addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                    char addrBuf[64];
                    if (inet_ntop(addr->sin_family, &addr->sin_addr, addrBuf, sizeof(addrBuf))) {
                        NSString* addrStr = @(addrBuf);
                        if (addr->sin_family==AF_INET)
                            [addresses insertObject: addrStr atIndex: ipv4count++];
                        else
                            [addresses addObject: addrStr];     // put ipv6 addrs at the end
                    }
                }
            }
        }
        freeifaddrs(interfaces);
    }
    return addresses;
}
