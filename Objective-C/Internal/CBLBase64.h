//
//  CBLBase64.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-ios/blob/master/Source/CBLBase64.h
//  Created by Jens Alfke on 9/14/11.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
