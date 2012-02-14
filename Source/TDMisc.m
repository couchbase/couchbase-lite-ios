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
#import <CommonCrypto/CommonDigest.h>


NSString* const TDHTTPErrorDomain = @"TDHTTP";


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
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)docOrRevID,
                                                                  NULL, (CFStringRef)@"&/",
                                                                  kCFStringEncodingUTF8);
    return [NSMakeCollectable(escaped) autorelease];
}


NSString* TDEscapeURLParam( NSString* param ) {
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)param,
                                                                  NULL, (CFStringRef)@"&",
                                                                  kCFStringEncodingUTF8);
    return [NSMakeCollectable(escaped) autorelease];
}


BOOL TDIsOfflineError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain))
        return code == NSURLErrorDNSLookupFailed
            || code == NSURLErrorNotConnectedToInternet
            || code == NSURLErrorInternationalRoamingOff;
    return NO;
}
