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

NSString* slice2string(C4Slice s) {
    if (!s.buf)
        return nil;
    return [[NSString alloc] initWithBytes: s.buf length: s.size encoding:NSUTF8StringEncoding];
}

C4Slice data2slice(NSData *data) {
    return {data.bytes, data.length};
}

NSString* sliceResult2string(C4SliceResult slice) {
    NSString* s = slice2string(C4Slice{slice.buf, slice.size});
    c4slice_free(slice);
    return s;
}

NSData* sliceResult2data(C4SliceResult slice) {
    if (!slice.buf)
        return nil;
    return [[NSData alloc] initWithBytesNoCopy: (void*)slice.buf length: slice.size
                                   deallocator: ^(void *bytes, NSUInteger length) {
                                       c4slice_free({bytes, length});
                                   }];
}

NSString* sliceResult2FilesystemPath(C4SliceResult str) {
    if (!str.buf)
        return nil;
    NSString* path = [NSFileManager.defaultManager
                            stringWithFileSystemRepresentation: (const char*)str.buf
                                                        length: str.size];
    c4slice_free(str);
    return path;
}
