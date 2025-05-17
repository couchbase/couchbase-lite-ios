//
//  CBLTrustCheck.h
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
#import <Security/SecTrust.h>
#import "CBLReplicatorConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLTrustCheck : NSObject

+ (void) setAnchorCerts: (NSArray*)certs onlyThese: (BOOL)onlyThese;

- (instancetype) initWithChallenge: (NSURLAuthenticationChallenge*)challenge;

- (instancetype) initWithTrust: (SecTrustRef)trust;

- (instancetype) initWithTrust: (SecTrustRef)trust host: (nullable NSString*)host port: (uint16_t)port;

@property (nonatomic, nullable) NSData* pinnedCertData;

#ifdef COUCHBASE_ENTERPRISE

@property (nonatomic) BOOL acceptOnlySelfSignedCert;

@property (nonatomic) NSArray* rootCerts;

#endif

- (nullable NSURLCredential*) checkTrust: (NSError**)outError;

- (void) forceTrusted;

@end

NS_ASSUME_NONNULL_END
