//
//  CBLMisc.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#ifdef __cplusplus
extern "C" {
#endif
    
NS_ASSUME_NONNULL_BEGIN

/** Generates UUID. */
NSString* __nullable CBLCreateUUID( void );

/** Writes a hex dump of the bytes to the output string.
 Returns a pointer to the end of the string (where it writes a null.) */
char* CBLAppendHex( char *dst, const void* bytes, size_t length);

/** Generates a hex dump of a sequence of bytes.
 The result is lowercase. This is important for CouchDB compatibility. */
NSString* CBLHexFromBytes( const void* bytes, size_t length);
    
/** Returns YES if this error appears to be due to a creating a file/dir that already exists. */
BOOL CBLIsFileExistsError( NSError* error );

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
