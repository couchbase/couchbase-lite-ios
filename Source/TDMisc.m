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


NSString* TDCreateUUID() {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString* str = NSMakeCollectable(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return [str autorelease];
}


NSString* TDHexSHA1Digest( NSData* input ) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(input.bytes, (CC_LONG)input.length, digest);
    return TDHexFromBytes(&digest, sizeof(digest));
}

NSString* TDHexFromBytes( const void* bytes, size_t length) {
    char hex[2*length + 1];
    char *dst = &hex[0];
    for( size_t i=0; i<length; i+=1 )
        dst += sprintf(dst,"%02x", ((const uint8_t*)bytes)[i]); // important: generates lowercase!
    return [[[NSString alloc] initWithBytes: hex
                                     length: 2*length
                                   encoding: NSASCIIStringEncoding] autorelease];
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


NSString* TDQuoteString( NSString* param ) {
    NSMutableString* quoted = [[param mutableCopy] autorelease];
    [quoted replaceOccurrencesOfString: @"\\" withString: @"\\\\"
                               options: NSLiteralSearch
                                 range: NSMakeRange(0, quoted.length)];
    [quoted replaceOccurrencesOfString: @"\"" withString: @"\\\""
                               options: NSLiteralSearch
                                 range: NSMakeRange(0, quoted.length)];
    [quoted insertString: @"\"" atIndex: 0];
    [quoted appendString: @"\""];
    return quoted;
}


NSString* TDUnquoteString( NSString* param ) {
    if (![param hasPrefix: @"\""])
        return param;
    if (![param hasSuffix: @"\""] || param.length < 2)
        return nil;
    param = [param substringWithRange: NSMakeRange(1, param.length - 2)];
    if ([param rangeOfString: @"\\"].length == 0)
        return param;
    NSMutableString* unquoted = [[param mutableCopy] autorelease];
    for (NSUInteger pos = 0; pos < unquoted.length; ) {
        NSRange r = [unquoted rangeOfString: @"\\"
                                    options: NSLiteralSearch
                                      range: NSMakeRange(pos, unquoted.length-pos)];
        if (r.length == 0)
            break;
        [unquoted deleteCharactersInRange: r];
        pos = r.location + 1;
        if (pos > unquoted.length)
            return nil;
    }
    return unquoted;
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



TestCase(TDQuoteString) {
    CAssertEqual(TDQuoteString(@""), @"\"\"");
    CAssertEqual(TDQuoteString(@"foo"), @"\"foo\"");
    CAssertEqual(TDQuoteString(@"f\"o\"o"), @"\"f\\\"o\\\"o\"");
    CAssertEqual(TDQuoteString(@"\\foo"), @"\"\\\\foo\"");
    CAssertEqual(TDQuoteString(@"\""), @"\"\\\"\"");
    CAssertEqual(TDQuoteString(@""), @"\"\"");

    CAssertEqual(TDUnquoteString(@""), @"");
    CAssertEqual(TDUnquoteString(@"\""), nil);
    CAssertEqual(TDUnquoteString(@"\"\""), @"");
    CAssertEqual(TDUnquoteString(@"\"foo"), nil);
    CAssertEqual(TDUnquoteString(@"foo\""), @"foo\"");
    CAssertEqual(TDUnquoteString(@"foo"), @"foo");
    CAssertEqual(TDUnquoteString(@"\"foo\""), @"foo");
    CAssertEqual(TDUnquoteString(@"\"f\\\"o\\\"o\""), @"f\"o\"o");
    CAssertEqual(TDUnquoteString(@"\"\\foo\""), @"foo");
    CAssertEqual(TDUnquoteString(@"\"\\\\foo\""), @"\\foo");
    CAssertEqual(TDUnquoteString(@"\"foo\\\""), nil);
}