//
//  CBLMisc.m
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-ios/blob/master/Source/CBLMisc.m
//  Created by Jens Alfke on 1/13/12.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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


NSString* CBLHexFromBytes( const void* bytes, size_t length) {
    char hex[2*length + 1];
    CBLAppendHex(hex, bytes, length);
    return [[NSString alloc] initWithBytes: hex
                                    length: 2*length
                                  encoding: NSASCIIStringEncoding];
}


BOOL CBLIsFileExistsError( NSError* error ) {
    NSString* domain = error.domain;
    NSInteger code = error.code;
    return ($equal(domain, NSPOSIXErrorDomain) && code == EEXIST)
        || ($equal(domain, NSCocoaErrorDomain) && code == NSFileWriteFileExistsError);
}
