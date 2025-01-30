//
//  CBLStringBytes.h
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

#import <Foundation/Foundation.h>
#import "c4Base.h"
#import "fleece/slice.hh"


/** A slice holding the data of an NSString. If possible, it points the slice into the data of the
    NSString, requiring no copying. Otherwise it copies the characters into a small internal
    stack based buffer if the inline storage is enabled, or into a temporary heap block.
    NOTE:
    - Since the slice may point directly into the NSString, if the string is mutable do not
      mutate it while the stringBytes object is in scope! (Releasing the string is OK, as
      stringBytes retains it.)
    - Dissable the inline storage If the CBLStringBytes is used outside the scope that is created as
      the inline storage (_local) is a stack base storage.
 */
struct CBLStringBytes {
    CBLStringBytes(NSString* str = nil, bool useLocalBuffer = true)
    : _useLocalBuffer(useLocalBuffer)
    {
        *this = str;
    }

    void operator= (NSString*);

    operator C4Slice() const        { return bytes; }
    
    operator fleece::slice() const  { return bytes; }

    fleece::slice bytes;

private:
    __strong id _storage {nullptr};       // keeps string alive, if `buf` points into it
    char _local[64];
    bool _useLocalBuffer;
};
