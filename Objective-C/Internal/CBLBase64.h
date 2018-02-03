//
//  CBLBase64.h
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

@interface CBLBase64 : NSObject
+ (NSString*) encode:(const void*) input length:(size_t) length;
+ (NSString*) encode:(NSData*) rawBytes;
+ (NSData*) decode:(const char*) string length:(size_t) inputLength;
+ (NSData*) decode:(NSString*) string;

/** Decodes the URL-safe Base64 variant that uses '-' and '_' instead of '+' and '/', and omits trailing '=' characters. */
+ (NSData*) decodeURLSafe: (NSString*)string;
+ (NSData*) decodeURLSafe: (const char*)string length: (size_t)inputLength;
@end
