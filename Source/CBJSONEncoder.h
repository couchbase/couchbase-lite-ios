//
//  CBJSONEncoder.h
//  CBJSON
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

/** Encodes Cocoa objects to JSON. Supports canonical encoding. */
@interface CBJSONEncoder : NSObject

- (instancetype) init;

- (BOOL) encode: (id)object;

/** If YES, JSON will be generated in canonical form, with consistently-ordered dictionary keys. */
@property BOOL canonical;

@property (readonly, nonatomic) NSError* error;
@property (readonly, nonatomic) NSData* encodedData;

+ (NSData*) encode: (id)object error: (NSError**)outError;
+ (NSData*) canonicalEncoding: (id)object error: (NSError**)outError;

/** Returns the dictionary's keys in the canonical order. */
+ (NSArray*) orderedKeys: (NSDictionary*)dict;

// PROTECTED:
@property (readonly, nonatomic) NSMutableData* output;
- (BOOL) encodeKey: (id)key value: (id)value;
- (BOOL) encodeNestedObject: (id)object;

@end

extern NSString* const CBJSONEncoderErrorDomain;
