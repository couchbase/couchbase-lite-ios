//
//  TDMisc.m
//  TouchDB
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDMisc.h"

#import "CollectionUtils.h"


#ifdef GNUSTEP
#import <openssl/sha.h>
#import <uuid/uuid.h>   // requires installing "uuid-dev" package on Ubuntu
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#endif


NSString* const TDHTTPErrorDomain = @"TDHTTP";


NSString* TDCreateUUID() {
#ifdef GNUSTEP
    uuid_t uuid;
    uuid_generate(uuid);
    char cstr[37];
    uuid_unparse_lower(uuid, cstr);
    return [[[NSString alloc] initWithCString: cstr encoding: NSASCIIStringEncoding] autorelease];
#else
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* str = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return [str autorelease];
#endif
}


NSString* TDHexSHA1Digest( NSData* input ) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    char hex[2*sizeof(digest) + 1];
    char *dst = &hex[0];
    for( size_t i=0; i<sizeof(digest); i+=1 )
        dst += sprintf(dst,"%02X", digest[i]);
    return [[[NSString alloc] initWithBytes: hex
                                     length: 2*sizeof(digest)
                                   encoding: NSASCIIStringEncoding] autorelease];
}


NSError* TDHTTPError( int status, NSURL* url ) {
    NSString* reason = [NSHTTPURLResponse localizedStringForStatusCode: status];
    NSDictionary* info = $dict({NSURLErrorKey, url},
                               {NSLocalizedFailureReasonErrorKey, reason},
                               {NSLocalizedDescriptionKey, $sprintf(@"%i %@", status, reason)});
    return [NSError errorWithDomain: TDHTTPErrorDomain code: status userInfo: info];
}


NSComparisonResult TDSequenceCompare( SequenceNumber a, SequenceNumber b) {
    SInt64 diff = a - b;
    return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}


NSString* TDEscapeID( NSString* docOrRevID ) {
#ifdef GNUSTEP
    docOrRevID = [docOrRevID stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    docOrRevID = [docOrRevID stringByReplacingOccurrencesOfString: @"&" withString: @"%26"];
    docOrRevID = [docOrRevID stringByReplacingOccurrencesOfString: @"/" withString: @"%2F"];
    return docOrRevID;
#else
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)docOrRevID,
                                                                  NULL, (CFStringRef)@"&/",
                                                                  kCFStringEncodingUTF8);
    return [NSMakeCollectable(escaped) autorelease];
#endif
}


NSString* TDEscapeURLParam( NSString* param ) {
#ifdef GNUSTEP
    param = [param stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    param = [param stringByReplacingOccurrencesOfString: @"&" withString: @"%26"];
    return param;
#else
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)param,
                                                                  NULL, (CFStringRef)@"&",
                                                                  kCFStringEncodingUTF8);
    return [NSMakeCollectable(escaped) autorelease];
#endif
}


BOOL TDIsOfflineError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain))
        return code == NSURLErrorDNSLookupFailed
            || code == NSURLErrorNotConnectedToInternet
#ifndef GNUSTEP
            || code == NSURLErrorInternationalRoamingOff
#endif
        ;
    return NO;
}


NSURL* TDURLWithoutQuery( NSURL* url ) {
#if GNUSTEP
    CAssert(NO, @"UNIMPLEMENTED"); //TEMP
#else
    // Strip anything after the URL's path (i.e. the query string)
    CFURLRef cfURL = (CFURLRef)url;
    CFRange range = CFURLGetByteRangeForComponent(cfURL, kCFURLComponentResourceSpecifier, NULL);
    if (range.length == 0) {
        return url;
    } else {
        CFIndex size = CFURLGetBytes(cfURL, NULL, 0);
        if (size > 8000)
            return url;  // give up
        UInt8 bytes[size];
        CFURLGetBytes(cfURL, bytes, size);
        cfURL = CFURLCreateWithBytes(NULL, bytes, range.location - 1, kCFStringEncodingUTF8, NULL);
        return [NSMakeCollectable(cfURL) autorelease];
    }
#endif
}
