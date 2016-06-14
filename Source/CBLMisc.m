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
#import "CBLBase64.h"

#import "CollectionUtils.h"
#import "CBJSONEncoder.h"
#import "CBLJSON.h"
#import <netdb.h>


#ifdef GNUSTEP
#import <openssl/sha.h>
#import <uuid/uuid.h>   // requires installing "uuid-dev" package on Ubuntu
#else
#define COMMON_DIGEST_FOR_OPENSSL
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#endif


UsingLogDomain(Database);


#if DEBUG
NSString* CBLPathToTestFile(NSString* name) {
    // The iOS and Mac test apps have the TestData folder copied into their Resources dir.
    NSString* path =  [[NSBundle mainBundle] pathForResource: name.stringByDeletingPathExtension
                                                      ofType: name.pathExtension
                                                 inDirectory: @"TestData"];
    Assert(path, @"Can't find test file \"%@\"", name);
    return path;
}

NSData* CBLContentsOfTestFile(NSString* name) {
    NSError* error;
    NSData* data = [NSData dataWithContentsOfFile: CBLPathToTestFile(name) options:0 error: &error];
    Assert(data, @"Couldn't read test file '%@': %@", name, error.my_compactDescription);
    return data;
}
#endif


BOOL CBLWithStringBytes(UU NSString* str, void (^block)(const char*, size_t)) {
    if (!str) {
        block(NULL, 0);
        return YES;
    }
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
    // Generate 136 bits of entropy in base64:
    uint8_t random[17];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(random), random) != 0)
        return nil;
    NSMutableString* uuid = [[CBLBase64 encode: random length: sizeof(random)] mutableCopy];
    // Trim the two trailing '=' padding characters:
    [uuid deleteCharactersInRange: NSMakeRange(22, 2)];
    // URL-safe character set per RFC 4648 sec. 5:
    [uuid replaceOccurrencesOfString: @"/" withString: @"_" options: 0 range: NSMakeRange(0, 22)];
    [uuid replaceOccurrencesOfString: @"+" withString: @"-" options: 0 range: NSMakeRange(0, 22)];
    // prefix a '!' to make it more clear where this string came from and prevent having a leading
    // '_' character:
    [uuid insertString: @"-" atIndex: 0];
    return uuid;
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

char* CBLAppendHex( char *dst, const void* bytes, size_t length) {
    const uint8_t* chars = bytes;
    static const char kDigit[16] = "0123456789abcdef";
    for( size_t i=0; i<length; i++ ) {
        *(dst++) = kDigit[chars[i] >> 4];
        *(dst++) = kDigit[chars[i] & 0xF];
    }
    *dst = '\0';
    return dst;
}

size_t CBLAppendDecimal(char *str, uint64_t n) {
    size_t len;
    if (n < 10) {
        str[0] = '0' + (char)n;
        len = 1;
    } else {
        char temp[20]; // max length is 20 decimal digits
        char *dst = &temp[20];
        len = 0;
        do {
            *(--dst) = '0' + (n % 10);
            n /= 10;
            len++;
        } while (n > 0);
        memcpy(str, dst, len);
    }
    str[len] = '\0';
    return len;
}

NSString* CBLHexFromBytes( const void* bytes, size_t length) {
    char hex[2*length + 1];
    CBLAppendHex(hex, bytes, length);
    return [[NSString alloc] initWithBytes: hex
                                    length: 2*length
                                  encoding: NSASCIIStringEncoding];
}

NSData* CBLDataFromHex(NSString* hex) {
    const char* chars = hex.UTF8String;
    NSUInteger len = strlen(chars);
    if (len % 2)
        return nil;
    NSMutableData* data = [NSMutableData dataWithLength: len/2];
    uint8_t *bytes = data.mutableBytes;
    NSUInteger bytePos = 0;
    for (NSUInteger i = 0; i < len; i += 2) {
        int d1 = chars[i], d2 = chars[i+1];
        if (!ishexnumber(d1) || !ishexnumber(d2))
            return nil;
        bytes[bytePos++] = (uint8_t)(16 * digittoint(d1) + digittoint(d2));
    }
    return data;
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


NSString* CBLDigestFromObject(id obj) {
    NSData* json = [CBJSONEncoder canonicalEncoding: obj error: NULL];
    Assert(json, @"CBLKeyFromObject got unencodable param");
    return [CBLJSON base64StringWithData: CBLSHA1Digest(json)];
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
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorDNSLookupFailed
            || code == NSURLErrorNotConnectedToInternet
#ifndef GNUSTEP
            || code == NSURLErrorInternationalRoamingOff
#endif
        ;
    } else if ($equal(domain, (__bridge id)kCFErrorDomainCFNetwork)) {
        if (code == kCFHostErrorUnknown) {
            int netdbCode = [error.userInfo[(__bridge id)kCFGetAddrInfoFailureKey] intValue];
            return netdbCode == EAI_NONAME;
        } else {
            return code == kCFHostErrorHostNotFound;
        }
    }
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

BOOL CBLIsFileNotFoundError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == ENOENT)
#ifndef GNUSTEP
        || ($equal(domain, NSCocoaErrorDomain) && (code == NSFileNoSuchFileError ||
                                                   code == NSFileReadNoSuchFileError))
#endif
    ;
}


BOOL CBLMayBeTransientError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    if ($equal(domain, NSURLErrorDomain)) {
        return code == NSURLErrorTimedOut || code == NSURLErrorCannotConnectToHost
                                          || code == NSURLErrorNetworkConnectionLost;
    } else if ($equal(domain, NSPOSIXErrorDomain)) {
        return code == ENETDOWN || code == ENETUNREACH || code == ENETRESET || code == ECONNABORTED
            || code == ECONNRESET || code == ETIMEDOUT || code == ECONNREFUSED;
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
        LogTo(Database, @"Deleted file %@", path);
        return YES;
    } else if (CBLIsFileNotFoundError(error)) {
        return YES;
    } else {
        if (outError)
            *outError = error;
        return NO;
    }
}

BOOL CBLRemoveFileIfExistsAsync(NSString* path, NSError** outError) {
    NSString* renamedPath = [NSTemporaryDirectory()
                             stringByAppendingPathComponent: CBLCreateUUID()];
    NSError* error;
    BOOL result = [[NSFileManager defaultManager] moveItemAtPath: path
                                                          toPath: renamedPath
                                                           error: &error];
    if (result) {
        LogTo(Database, @"Renamed file %@ to %@ for async delete", renamedPath, renamedPath);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSError* outError;
            if (CBLRemoveFileIfExists(renamedPath, &outError))
                LogTo(Database, @"Deleted file %@", renamedPath);
            else
                Warn(@"Failed to delete an attachment folder at %@ with error: %@",
                     renamedPath, outError);
        });
        return YES;
    } else if (CBLIsFileNotFoundError(error)) {
        return YES;
    } else {
        if (outError)
            *outError = error;
        return NO;
    }
}


BOOL CBLCopyFileIfExists(NSString* atPath, NSString* toPath, NSError** outError) {
    NSFileManager *fmgr = [NSFileManager defaultManager];
    if ([fmgr fileExistsAtPath:atPath isDirectory:NULL]) {
        NSError *error;
        if ([fmgr copyItemAtPath: atPath toPath: toPath error: &error])
            return YES;
        else {
            if (outError)
                *outError = error;
            return NO;
        }
    } else
        return YES;
}


BOOL CBLSafeReplaceDir(NSString* srcPath, NSString* dstPath, NSError** outError) {
    NSFileManager* fmgr = [NSFileManager defaultManager];
    // Define an interim location to move dstPath to, and make sure it's available:
    NSString* interimPath = [dstPath stringByAppendingString: @"~"];
    [fmgr removeItemAtPath: interimPath error: NULL];

    if ([fmgr moveItemAtPath: dstPath toPath: interimPath error: outError]) {
        if ([fmgr moveItemAtPath: srcPath toPath: dstPath error: outError]) {
            [fmgr removeItemAtPath: interimPath error: NULL];
            return YES; // success!
        }
        [fmgr moveItemAtPath: interimPath toPath: dstPath error: NULL]; // back out
    }
    return NO;
}


NSString* CBLGetHostName() {
    // From <http://stackoverflow.com/a/16902907/98077>
    char baseHostName[256];
    if (gethostname(baseHostName, 255) != 0)
        return nil;
    baseHostName[255] = '\0';
    NSString* hostName = [NSString stringWithUTF8String: baseHostName];
#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    if (![hostName hasSuffix: @".local"])
        hostName = [hostName stringByAppendingString: @".local"];
#endif
    return hostName;
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


id CBLKeyForPrefixMatch(id key, unsigned depth) {
    if (depth < 1)
        return key;
    if ([key isKindOfClass: [NSString class]]) {
        // Kludge: prefix match a string by appending max possible character value to it
        return [key stringByAppendingString: @"\uffffffff"];
    } else if ([key isKindOfClass: [NSArray class]]) {
        NSMutableArray* nuKey = [key mutableCopy];
        if (depth == 1) {
            [nuKey addObject: @{}];
        } else {
            id lastObject = CBLKeyForPrefixMatch(nuKey.lastObject, depth-1);
            [nuKey replaceObjectAtIndex: nuKey.count-1 withObject: lastObject];
        }
        return nuKey;
    } else {
        return key;
    }
}


NSString* CBLStemmerNameForCurrentLocale(void) {
    // Derive the stemmer language name based on the current locale's language.
    // For NSLocale language codes see https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
    // The tokenizer hardcodes language names; see unicodeSetStemmer() in fts3_unicodesn.c.
    return [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
}
