//
//  CBLEncryptionKey.m
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

#import "CBLEncryptionKey.h"
#import "CBLEncryptionKey+Internal.h"
#import <CommonCrypto/CommonCrypto.h>

#define kKeySize kCCKeySizeAES256
#define kDefaultSalt @"Salty McNaCl"
#define kDefaultPBKDFRounds 64000 // Same as what SQLCipher uses

@implementation CBLEncryptionKey

@synthesize key=_key;


- (instancetype) initWithKey: (NSData*)key {
    self = [super init];
    if (self) {
        if (key.length != kKeySize) {
            [NSException raise: NSInternalInconsistencyException
                        format: @"Key size is invalid. Key must be a 256-bit (32-byte) key."];
        }
        _key = [key copy];
    }
    return self;
}


- (instancetype) initWithPassword: (NSString*)password {
    return [self initWithPassword: password
                             salt: [kDefaultSalt dataUsingEncoding: NSUTF8StringEncoding]
                           rounds: kDefaultPBKDFRounds];
}


- (instancetype) initWithPassword: (NSString*)password
                             salt: (NSData*)salt
                           rounds: (uint32_t)rounds
{
    Assert(password);
    Assert(salt.length > 4, @"Insufficient salt");
    Assert(rounds > 200, @"Insufficient rounds");
    NSMutableData* keyData = [NSMutableData dataWithLength: kKeySize];
    NSData* passwordData = [password dataUsingEncoding: NSUTF8StringEncoding];
    int status = CCKeyDerivationPBKDF(kCCPBKDF2,
                                      passwordData.bytes, passwordData.length,
                                      salt.bytes, salt.length,
                                      kCCPRFHmacAlgSHA256, rounds,
                                      keyData.mutableBytes, keyData.length);
    if (status) {
        return nil;
    }
    return [self initWithKey: keyData];
}


@end
