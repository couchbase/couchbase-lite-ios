//
//  TDBase64.h
//  TouchDB
//
//  Created by Jens Alfke on 9/14/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TDBase64 : NSObject
+ (NSString*) encode:(const void*) input length:(size_t) length;
+ (NSString*) encode:(NSData*) rawBytes;
+ (NSData*) decode:(const char*) string length:(size_t) inputLength;
+ (NSData*) decode:(NSString*) string;
@end