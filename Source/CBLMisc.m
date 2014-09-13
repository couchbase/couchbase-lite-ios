//
//  CBLMisc.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/13/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLMisc.h"

#import "CollectionUtils.h"


#ifdef GNUSTEP
#import <openssl/sha.h>
#import <uuid/uuid.h>   // requires installing "uuid-dev" package on Ubuntu
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#endif


#if DEBUG
NSString* CBLPathToTestFile(NSString* name) {
    // The iOS and Mac test apps have the TestData folder copied into their Resources dir.
    return [[NSBundle mainBundle] pathForResource: name.stringByDeletingPathExtension
                                           ofType: name.pathExtension
                                      inDirectory: @"TestData"];
}

NSData* CBLContentsOfTestFile(NSString* name) {
    NSError* error;
    NSData* data = [NSData dataWithContentsOfFile: CBLPathToTestFile(name) options:0 error: &error];
    Assert(data, @"Couldn't read test file '%@': %@", name, error);
    return data;
}
#endif


BOOL CBLWithStringBytes(UU NSString* str, void (^block)(const char*, size_t)) {
    // First attempt: Get a C string directly from the CFString if it's in the right format:
    const char* cstr = CFStringGetCStringPtr((CFStringRef)str, kCFStringEncodingUTF8);
    if (cstr) {
        block(cstr, strlen(cstr));
        return YES;
    }

    NSUInteger byteCount;
    if (str.length < 256) {
        // First try to copy the UTF-8 into a smallish stack-based buffer:
        char stackBuf[256];
        NSRange remaining;
        BOOL ok = [str getBytes: stackBuf maxLength: sizeof(stackBuf) usedLength: &byteCount
                       encoding: NSUTF8StringEncoding options: 0
                          range: NSMakeRange(0, str.length) remainingRange: &remaining];
        if (ok && remaining.length == 0) {
            block(stackBuf, byteCount);
            return YES;
        }
    }

    // Otherwise malloc a buffer to copy the UTF-8 into:
    NSUInteger maxByteCount = [str maximumLengthOfBytesUsingEncoding: NSUTF8StringEncoding];
    char* buf = malloc(maxByteCount);
    if (!buf)
        return NO;
    BOOL ok = [str getBytes: buf maxLength: maxByteCount usedLength: &byteCount
                   encoding: NSUTF8StringEncoding options: 0
                      range: NSMakeRange(0, str.length) remainingRange: NULL];
    if (ok)
        block(buf, byteCount);
    free(buf);
    return ok;
}


NSString* CBLCreateUUID() {
#ifdef GNUSTEP
    uuid_t uuid;
    uuid_generate(uuid);
    char cstr[37];
    uuid_unparse_lower(uuid, cstr);
    return [[[NSString alloc] initWithCString: cstr encoding: NSASCIIStringEncoding] autorelease];
#else
    
    CFUUIDRef uuid = CFUUIDCreate(NULL);
#ifdef __OBJC_GC__
    CFStringRef uuidStrRef = CFUUIDCreateString(NULL, uuid);
    NSString *uuidStr = (NSString *)uuidStrRef;
    CFRelease(uuidStrRef);
#else
    NSString *uuidStr = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
#endif
    CFRelease(uuid);
    return uuidStr;
#endif
}


NSData* CBLSHA1Digest( NSData* input ) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}

NSData* CBLSHA256Digest( NSData* input ) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256_CTX ctx;
    SHA256_Init(&ctx);
    SHA256_Update(&ctx, input.bytes, input.length);
    SHA256_Final(digest, &ctx);
    return [NSData dataWithBytes: &digest length: sizeof(digest)];
}


NSString* CBLHexSHA1Digest( NSData* input ) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;
    SHA1_Init(&ctx);
    SHA1_Update(&ctx, input.bytes, input.length);
    SHA1_Final(digest, &ctx);
    return CBLHexFromBytes(&digest, sizeof(digest));
}

NSString* CBLHexFromBytes( const void* bytes, size_t length) {
    char hex[2*length + 1];
    char *dst = &hex[0];
    for( size_t i=0; i<length; i+=1 )
        dst += sprintf(dst,"%02x", ((const uint8_t*)bytes)[i]); // important: generates lowercase!
    return [[NSString alloc] initWithBytes: hex
                                     length: 2*length
                                   encoding: NSASCIIStringEncoding];
}


NSData* CBLHMACSHA1(NSData* key, NSData* data) {
    UInt8 hmac[SHA_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA1, key.bytes, key.length, data.bytes, data.length, &hmac);
    return [NSData dataWithBytes: hmac length: sizeof(hmac)];
}

NSData* CBLHMACSHA256(NSData* key, NSData* data) {
    UInt8 hmac[SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, &hmac);
    return [NSData dataWithBytes: hmac length: sizeof(hmac)];
}


NSComparisonResult CBLSequenceCompare( SequenceNumber a, SequenceNumber b) {
    SInt64 diff = a - b;
    return diff > 0 ? 1 : (diff < 0 ? -1 : 0);
}


NSString* CBLJSONString( id object ) {
    if (!object)
        return nil;
    return [CBLJSON stringWithJSONObject: object
                                 options: CBLJSONWritingAllowFragments
                                   error: NULL];
}


NSString* CBLEscapeURLParam( NSString* param ) {
    // Escape all of the reserved characters according to section 2.2 in rfc3986
    // http://tools.ietf.org/html/rfc3986#section-2.2
#ifdef GNUSTEP
    param = [param stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
    param = [param stringByReplacingOccurrencesOfString: @":" withString: @"%3A"];
    param = [param stringByReplacingOccurrencesOfString: @"/" withString: @"%2F"];
    param = [param stringByReplacingOccurrencesOfString: @"?" withString: @"%3F"];
    param = [param stringByReplacingOccurrencesOfString: @"@" withString: @"%40"];
    param = [param stringByReplacingOccurrencesOfString: @"!" withString: @"%21"];
    param = [param stringByReplacingOccurrencesOfString: @"$" withString: @"%24"];
    param = [param stringByReplacingOccurrencesOfString: @"&" withString: @"%26"];
    param = [param stringByReplacingOccurrencesOfString: @"'" withString: @"%27"];
    param = [param stringByReplacingOccurrencesOfString: @"(" withString: @"%28"];
    param = [param stringByReplacingOccurrencesOfString: @")" withString: @"%29"];
    param = [param stringByReplacingOccurrencesOfString: @"*" withString: @"%2A"];
    param = [param stringByReplacingOccurrencesOfString: @"+" withString: @"%2B"];
    param = [param stringByReplacingOccurrencesOfString: @"," withString: @"%2C"];
    param = [param stringByReplacingOccurrencesOfString: @";" withString: @"%3B"];
    param = [param stringByReplacingOccurrencesOfString: @"=" withString: @"%3D"];
    return param;
#else
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                  (CFStringRef)param,
                                                                  NULL,
                                                                  (CFStringRef)@":/?@!$&'()*+,;=",
                                                                  kCFStringEncodingUTF8);
    #ifdef __OBJC_GC__
    return NSMakeCollectable(escaped);
    #else
    return (__bridge_transfer NSString *)escaped;
    #endif
#endif
}


NSString* CBLQuoteString( NSString* param ) {
    NSMutableString* quoted = [param mutableCopy];
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


NSString* CBLUnquoteString( NSString* param ) {
    if (![param hasPrefix: @"\""])
        return param;
    if (![param hasSuffix: @"\""] || param.length < 2)
        return nil;
    param = [param substringWithRange: NSMakeRange(1, param.length - 2)];
    if ([param rangeOfString: @"\\"].length == 0)
        return param;
    NSMutableString* unquoted = [param mutableCopy];
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


NSString* CBLAbbreviate( NSString* str ) {
    if (str.length <= 10)
        return str;
    NSMutableString* abbrev = [str mutableCopy];
    [abbrev replaceCharactersInRange: NSMakeRange(4, abbrev.length - 8) withString: @".."];
    return abbrev;
}


BOOL CBLParseInteger(NSString* str, NSInteger* outInt) {
    NSScanner* scanner = [[NSScanner alloc] initWithString: str];
    return [scanner scanInteger: outInt] && [scanner isAtEnd];
}


BOOL CBLIsOfflineError( NSError* error ) {
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


BOOL CBLIsFileExistsError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == EEXIST)
#ifndef GNUSTEP
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileWriteFileExistsError)
#endif
        ;
}

static BOOL CBLIsFileNotFoundError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == ENOENT)
#ifndef GNUSTEP
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileNoSuchFileError)
#endif
    ;
}


BOOL CBLMayBeTransientError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorTimedOut || code == NSURLErrorCannotConnectToHost
                                          || code == NSURLErrorNetworkConnectionLost;
    } else if ($equal(domain, CBLHTTPErrorDomain)) {
        // Internal Server Error, Bad Gateway, Service Unavailable or Gateway Timeout:
        return code == 500 || code == 502 || code == 503 || code == 504;
    } else {
        return NO;
    }
}


BOOL CBLIsPermanentError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorBadURL
            || code == NSURLErrorUnsupportedURL
            || code == NSURLErrorUserCancelledAuthentication
            || code == NSURLErrorUserAuthenticationRequired
            || (code <= NSURLErrorSecureConnectionFailed &&
                code >= NSURLErrorClientCertificateRequired);
    } else if ($equal(domain, CBLHTTPErrorDomain)) {
        return code >= 400 && code <= 499;
    } else {
        return NO;
    }
}


BOOL CBLRemoveFileIfExists(NSString* path, NSError** outError) {
    NSError* error;
    if ([[NSFileManager defaultManager] removeItemAtPath: path error: &error]) {
        LogTo(CBLDatabase, @"Deleted file %@", path);
        return YES;
    } else if (CBLIsFileNotFoundError(error)) {
        return YES;
    } else {
        if (outError)
            *outError = error;
        return NO;
    }
}


NSURL* CBLURLWithoutQuery( NSURL* url ) {
#ifdef GNUSTEP
    // No CFURL on GNUstep :(
    NSString* str = url.absoluteString;
    NSRange q = [str rangeOfString: @"?"];
    if (q.length == 0)
        return url;
    return [NSURL URLWithString: [str substringToIndex: q.location]];
#else
    // Strip anything after the URL's path (i.e. the query string)
    CFURLRef cfURL = (__bridge CFURLRef)url;
    CFRange range = CFURLGetByteRangeForComponent(cfURL, kCFURLComponentResourceSpecifier, NULL);
    if (range.length == 0) {
        return url;
    } else {
        CFIndex size = CFURLGetBytes(cfURL, NULL, 0);
        if (size > 8000)
            return url;  // give up
        UInt8 bytes[size];
        CFURLGetBytes(cfURL, bytes, size);
        NSURL *url = (__bridge_transfer NSURL *)CFURLCreateWithBytes(NULL, bytes, range.location - 1, kCFStringEncodingUTF8, NULL);
    #ifdef __OBJC_GC__
        return NSMakeCollectable(url);
    #else
        return url;
    #endif
    }
#endif
}


NSURL* CBLAppendToURL(NSURL* baseURL, NSString* toAppend) {
    if (toAppend.length == 0 || $equal(toAppend, @"."))
        return baseURL;
    NSMutableString* urlStr = baseURL.absoluteString.mutableCopy;
    if (![urlStr hasSuffix: @"/"])
        [urlStr appendString: @"/"];
    [urlStr appendString: toAppend];
    return [NSURL URLWithString: urlStr];
}


TestCase(CBLQuoteString) {
    CAssertEqual(CBLQuoteString(@""), @"\"\"");
    CAssertEqual(CBLQuoteString(@"foo"), @"\"foo\"");
    CAssertEqual(CBLQuoteString(@"f\"o\"o"), @"\"f\\\"o\\\"o\"");
    CAssertEqual(CBLQuoteString(@"\\foo"), @"\"\\\\foo\"");
    CAssertEqual(CBLQuoteString(@"\""), @"\"\\\"\"");
    CAssertEqual(CBLQuoteString(@""), @"\"\"");

    CAssertEqual(CBLUnquoteString(@""), @"");
    CAssertEqual(CBLUnquoteString(@"\""), nil);
    CAssertEqual(CBLUnquoteString(@"\"\""), @"");
    CAssertEqual(CBLUnquoteString(@"\"foo"), nil);
    CAssertEqual(CBLUnquoteString(@"foo\""), @"foo\"");
    CAssertEqual(CBLUnquoteString(@"foo"), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"foo\""), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"f\\\"o\\\"o\""), @"f\"o\"o");
    CAssertEqual(CBLUnquoteString(@"\"\\foo\""), @"foo");
    CAssertEqual(CBLUnquoteString(@"\"\\\\foo\""), @"\\foo");
    CAssertEqual(CBLUnquoteString(@"\"foo\\\""), nil);
}


TestCase(CBLEscapeURLParam) {
    CAssertEqual(CBLEscapeURLParam(@"foobar"), @"foobar");
    CAssertEqual(CBLEscapeURLParam(@"<script>alert('ARE YOU MY DADDY?')</script>"),
                 @"%3Cscript%3Ealert%28%27ARE%20YOU%20MY%20DADDY%3F%27%29%3C%2Fscript%3E");
    CAssertEqual(CBLEscapeURLParam(@"foo/bar"), @"foo%2Fbar");
    CAssertEqual(CBLEscapeURLParam(@"foo&bar"), @"foo%26bar");
    CAssertEqual(CBLEscapeURLParam(@":/?#[]@!$&'()*+,;="),
                 @"%3A%2F%3F%23%5B%5D%40%21%24%26%27%28%29%2A%2B%2C%3B%3D");
}
