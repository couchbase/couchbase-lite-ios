//
//  CBLCoreBridge.mm
//  CouchbaseLite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLCoreBridge.h"
#import "fleece/slice.hh"

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
    return fleece::alloc_slice(slice).uncopiedNSData();
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
