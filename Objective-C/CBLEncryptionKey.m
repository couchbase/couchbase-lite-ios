//
//  CBLEncryptionKey.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 8/22/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
