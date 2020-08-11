//
//  TLSIdentityHelper.h
//  CouchbaseLite
//
//  Copyright (c) 2020 Couchbase, Inc All rights reserved.
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

#import <XCTest/XCTest.h>

@interface TLSIdentityHelper : NSObject

// saves the private key and certificates into keychain
+ (BOOL) storePrivateKey: (SecKeyRef)privateKey certs: (NSArray*)certs label: (NSString*)label;

// updates the label for the cerificate in keychain
+ (OSStatus) updateCert: (SecCertificateRef)cert withLabel: (NSString*)label;

@end
