//
//  CBLBase64.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 9/14/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
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
