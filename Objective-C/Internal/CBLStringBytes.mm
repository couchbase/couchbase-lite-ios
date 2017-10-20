//
//  CBLStringBytes.m
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-core/blob/master/Objective-C/StringBytes.mm
//  Created by Jens Alfke on 10/13/16.
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

#import "CBLStringBytes.h"

using namespace fleece;


CBLStringBytes::CBLStringBytes(__unsafe_unretained NSString* str) {
    *this = str;
}

void CBLStringBytes::operator= (__unsafe_unretained NSString* str) {
    if (!str) {
        bytes = nullslice;
        _storage = nil;
        return;
    }
    
    // First try to use a direct pointer to the bytes:
    auto cstr = CFStringGetCStringPtr((__bridge CFStringRef)str, kCFStringEncodingUTF8);
    if (cstr) {
        bytes = slice(cstr);
        _storage = str;
        return;
    }

    NSUInteger byteCount;
    NSUInteger length = str.length;
    if (length <= sizeof(_local)) {
        // Next try to copy the UTF-8 into a smallish stack-based buffer:
        NSRange remaining;
        BOOL ok = [str getBytes: _local maxLength: sizeof(_local) usedLength: &byteCount
                       encoding: NSUTF8StringEncoding options: 0
                          range: NSMakeRange(0, length) remainingRange: &remaining];
        if (ok && remaining.length == 0) {
            bytes = slice(_local, byteCount);
            _storage = nil;
            return;
        }
    }
    
    // Otherwise allocate the UTF-8 in an autoreleased heap block:
    NSData* data = [str dataUsingEncoding: NSUTF8StringEncoding];
    _storage = data;
    bytes = slice(data);
}

