//
//  CBLCoreBridge.m
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-core/blob/master/Objective-C/LC_Internal.mm
//  Created by Jens Alfke on 10/27/16.
//
//  Created by Pasin Suriyentrakorn on 12/30/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLCoreBridge.h"

BOOL convertError(const C4Error &c4err, NSError **outError) {
    NSCAssert(c4err.code != 0 && c4err.domain != 0, @"No C4Error");
    static NSString* const kDomains[] = {nil, @"LiteCore", NSPOSIXErrorDomain, @"ForestDB",
                                         @"SQLite", @"Fleece"};
    if (outError) {
        auto msg = c4error_getMessage(c4err);
        NSString* msgStr = [[NSString alloc] initWithBytes: msg.buf length: msg.size
                                                  encoding: NSUTF8StringEncoding];
        *outError = [NSError errorWithDomain: kDomains[c4err.domain] code: c4err.code
                                    userInfo: @{NSLocalizedDescriptionKey: msgStr}];
    }
    return NO;
}

BOOL convertError(const FLError &flErr, NSError **outError) {
    NSCAssert(flErr != 0, @"No C4Error");
    if (outError)
        *outError = [NSError errorWithDomain: FLErrorDomain code: flErr userInfo: nil];
    return NO;
}

NSString* slice2string(FLSlice s) {
    if (!s.buf)
        return nil;
    return [[NSString alloc] initWithBytes: s.buf length: s.size encoding:NSUTF8StringEncoding];
}

NSString* slice2string(C4Slice s) {
    if (!s.buf)
        return nil;
    return [[NSString alloc] initWithBytes: s.buf length: s.size encoding:NSUTF8StringEncoding];
}

C4EncryptionKey symmetricKey2C4Key(CBLSymmetricKey* key) {
    C4EncryptionKey cKey;
    if (key) {
        cKey.algorithm = kC4EncryptionAES256;
        NSCAssert(key.keyData.length == sizeof(cKey.bytes), @"Invalid key size");
        memcpy(cKey.bytes, key.keyData.bytes, sizeof(cKey.bytes));
    } else {
        cKey.algorithm = kC4EncryptionNone;
    }
    return cKey;
}
