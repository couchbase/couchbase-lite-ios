//
//  TDMisc.m
//  TouchDB
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDMisc.h"

#import <CommonCrypto/CommonDigest.h>


NSString* TDCreateUUID() {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* str = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return [str autorelease];
}


NSString* TDHexSHA1Digest( NSData* input ) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(input.bytes, (CC_LONG)input.length, digest);
    char hex[2*sizeof(digest) + 1];
    char *dst = &hex[0];
    for( size_t i=0; i<sizeof(digest); i+=1 )
        dst += sprintf(dst,"%02X", digest[i]);
    return [[[NSString alloc] initWithBytes: hex
                                     length: 2*sizeof(digest)
                                   encoding: NSASCIIStringEncoding] autorelease];
}
