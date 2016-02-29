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

#import "CBLListener+Internal.h"
#import "CBL_Server.h"
#import "CBLSyncListener.h"
#import "CBLHTTPListener.h"
#import "CBLMisc.h"
#import "MYAnonymousIdentity.h"


DefineLogDomain(Listener);


@implementation CBLListener
{
    UInt16 _explicitPort;
    NSDictionary* _passwords;
    SecIdentityRef _SSLIdentity;
}


@synthesize readOnly=_readOnly, requiresAuth=_requiresAuth, realm=_realm,
            SSLExtraCertificates=_SSLExtraCertificates, delegate=_delegate;


- (instancetype) initWithManager: (CBLManager*)manager port: (UInt16)port {
    if ([self class] == [CBLListener class]) {
        // If trying to instantiate CBLListener directly, choose appropriate subclass:
        NSString* className = @"CBLHTTPListener";
        if ([manager.replicatorClassName isEqualToString: @"CBLBlipReplicator"])
            className = @"CBLSyncListener";
        Class klass = NSClassFromString(className);
        Assert(klass, @"Concrete listener class %@ not found; make sure you've linked the necessary library", className);
        return [[klass alloc] initWithManager: manager port: port];
    } else {
        // Instantiating a subclass, so do my part:
        self = [super init];
        if (self) {
            _explicitPort = port;
            self.realm = @"CouchbaseLite";
        }
        return self;
    }
}


- (void)dealloc {
    [self stop];
    if (_SSLIdentity)
        CFRelease(_SSLIdentity);
}


- (void) setBonjourName: (NSString*)name type: (NSString*)type  {AssertAbstractMethod();}
- (NSString*) bonjourName                                       {AssertAbstractMethod();}
- (NSDictionary *)TXTRecordDictionary                           {AssertAbstractMethod();}
- (void)setTXTRecordDictionary:(NSDictionary *)dict             {AssertAbstractMethod();}
- (UInt16) port                                                 {AssertAbstractMethod();}
- (BOOL) start: (NSError**)outError                             {AssertAbstractMethod();}
- (void) stop                                                   { /* no-op*/ }


- (NSURL*) URL {
    NSString* hostName = CBLGetHostName();
    int port = (_explicitPort ?: self.port);
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
    id<CBLListenerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector: @selector(passwordForUser:)])
        return [delegate passwordForUser: username];
    else
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

- (NSArray *) SSLIdentityAndCertificates {
    if (!_SSLIdentity)
        return nil;
    NSMutableArray* result = [NSMutableArray arrayWithObject: (__bridge id)_SSLIdentity];
    if (_SSLExtraCertificates)
        [result addObjectsFromArray: _SSLExtraCertificates];
    LogTo(Listener, @"Using SSL identity/certs %@", result);
    return result;
}

@end
