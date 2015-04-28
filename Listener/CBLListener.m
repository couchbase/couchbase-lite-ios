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
#import "CBLMisc.h"
#import "Logging.h"
#import "MYAnonymousIdentity.h"

#import "HTTPServer.h"
#import "HTTPLogging.h"

#import <sys/types.h>
#import <sys/socket.h>
#import <net/if.h>
#import <netinet/in.h>
#import <ifaddrs.h>
#import <arpa/inet.h>


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
    NSString* hostName = CBLGetHostName();
    UInt16 port = self.port;
    if (port == 0 || hostName == nil)
        return nil;
    NSString* urlStr = [NSString stringWithFormat: @"http%@://%@:%d/",
                        (_SSLIdentity ? @"s" : @""), hostName, port];
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

- (BOOL) setAnonymousSSLIdentityWithLabel: (NSString*)label error: (NSError**)outError {
    SecIdentityRef identity = MYGetOrCreateAnonymousIdentity(label,
                                                     kMYAnonymousIdentityDefaultExpirationInterval,
                                                     outError);
    self.SSLIdentity = identity;
    self.SSLExtraCertificates = nil;
    return (identity != NULL);
}

- (NSData*) SSLIdentityDigest {
    if (!_SSLIdentity)
        return nil;
    SecCertificateRef cert = NULL;
    SecIdentityCopyCertificate(_SSLIdentity, &cert);
    if (!cert)
        return nil;
    NSData* digest = MYGetCertificateDigest(cert);
    CFRelease(cert);
    return digest;
}

+ (void) runTestCases {
#if DEBUG && MY_ENABLE_TESTS
    const char* argv[] = {"Test_All"};
    RunTestCases(1, argv);
#endif
}

@end



// Adapter to output DDLog messages (from CocoaHTTPServer) via MYUtilities logging.
@implementation CBL_MYDDLogger

- (void) logMessage:(DDLogMessage *)logMessage {
    Log(@"%@", logMessage->logMsg);
}

@end
