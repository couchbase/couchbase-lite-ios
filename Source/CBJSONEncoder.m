//
//  CBJSONEncoder.m
//  CBJSON
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#include "yajl/yajl_gen.h"


NSString* const CBJSONEncoderErrorDomain = @"CBJSONEncoder";


@interface CBJSONEncoder ()
@property (readwrite, nonatomic) NSError* error;
@end


@interface NSObject (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical;
@end

@interface NSDictionary (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen
                          canonical: (BOOL)canonical
                          keyFilter: (CBJSONEncoderKeyFilter)keyFilter
                              error: (NSError**)outError;
@end





@implementation CBJSONEncoder
{
    NSMutableData* _encoded;
    yajl_gen _gen;
    yajl_gen_status _status;
    NSError* _error;
}

@synthesize canonical=_canonical, keyFilter=_keyFilter;


+ (NSData*) encode: (UU id)object error: (NSError**)outError {
    CBJSONEncoder* encoder = [[self alloc] init];
    if ([encoder encode: object])
        return encoder.encodedData;
    else if (outError)
        *outError = encoder.error;
    return nil;
}

+ (NSData*) canonicalEncoding: (UU id)object error: (NSError**)outError {
    CBJSONEncoder* encoder = [[self alloc] init];
    encoder.canonical = YES;
    if ([encoder encode: object])
        return encoder.encodedData;
    else if (outError)
        *outError = encoder.error;
    return nil;
}


- (instancetype) init {
    self = [super init];
    if (self) {
        _encoded = [[NSMutableData alloc] initWithCapacity: 1024];
        _gen = yajl_gen_alloc(NULL);
        if (!_gen)
            return nil;
    }
    return self;
}


- (void) dealloc {
    if (_gen)
        yajl_gen_free(_gen);
}


- (BOOL) encode: (UU id)object {
    if (_keyFilter && [object isKindOfClass: [NSDictionary class]]) {
        NSError* error = nil;
        _status = [(NSDictionary*)object cbjson_encodeTo: _gen
                                               canonical: _canonical
                                               keyFilter: _keyFilter
                                                   error: &error];
        _error = error;
    } else {
        _status = [object cbjson_encodeTo: _gen canonical: _canonical];
    }
    return _status == yajl_gen_status_ok;
}


- (NSData*) encodedData {
    const uint8_t* buf;
    size_t len;
    yajl_gen_get_buf(_gen, &buf, &len);
    [_encoded appendBytes: buf length: len];
    yajl_gen_clear(_gen);
    return _encoded;
}

- (NSMutableData*) output {
    (void)[self encodedData];
    return _encoded;
}


- (NSError*) error {
    if (_error)
        return _error;
    else if (_status != yajl_gen_status_ok)
        return [NSError errorWithDomain: CBJSONEncoderErrorDomain code: _status userInfo: nil];
    else
        return nil;
}

- (void) setError:(NSError *)error {
    _error = error;
}


+ (NSArray*) orderedKeys: (UU NSDictionary*)dict {
    return [[dict allKeys] sortedArrayUsingComparator: ^NSComparisonResult(id s1, id s2) {
        return [s1 compare: s2 options: NSLiteralSearch];
        /* Alternate implementation in case NSLiteralSearch turns out to be inappropriate:
         NSUInteger len1 = [s1 length], len2 = [s2 length];
         unichar chars1[len1], chars2[len2];     //FIX: Will crash (stack overflow) on v. long strings
         [s1 getCharacters: chars1 range: NSMakeRange(0, len1)];
         [s2 getCharacters: chars2 range: NSMakeRange(0, len2)];
         NSUInteger minLen = MIN(len1, len2);
         for (NSUInteger i=0; i<minLen; i++) {
         if (chars1[i] > chars2[i])
         return 1;
         else if (chars1[i] < chars2[i])
         return -1;
         }
         // All chars match, so the longer string wins
         return (NSInteger)len1 - (NSInteger)len2; */
    }];
}


@end




@implementation NSString (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical {
    __block yajl_gen_status status = yajl_gen_invalid_string;
    CBLWithStringBytes(self, ^(const char *chars, size_t len) {
        status = yajl_gen_string(gen, (const unsigned char*)chars, len);
    });
    return status;
}
@end

@implementation NSNumber (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical {
    char ctype = self.objCType[0];
    switch (ctype) {
        case 'c': {
            // The only way to tell whether an NSNumber with 'char' type is a boolean is to
            // compare it against the singleton kCFBoolean objects:
            if (self == (id)kCFBooleanTrue)
                return yajl_gen_bool(gen, true);
            else if (self == (id)kCFBooleanFalse)
                return yajl_gen_bool(gen, false);
            else
                return yajl_gen_integer(gen, self.longLongValue);
        }
        case 'f':
        case 'd': {
            // Based on yajl_gen_double, except yajl uses too many significant figures (20 not 16)
            // which causes some numbers to round badly (e.g "8.9900000000000002" for "8.99")
            double n = self.doubleValue;
            char str[32];
            if (isnan(n) || isinf(n))  {
                return yajl_gen_invalid_number;
            }
            unsigned len = sprintf(str, (ctype=='f' ? "%.6g" : "%.16g"), n);
            if (strspn(str, "0123456789-") == strlen(str)) {
                strcat(str, ".0");
                len += 2;
            }
            return yajl_gen_number(gen, str, len);
        }
        case 'Q': {
            char str[32];
            unsigned len = sprintf(str, "%llu", self.unsignedLongLongValue);
            return yajl_gen_number(gen, str, len);
        }
        default:
            return yajl_gen_integer(gen, self.longLongValue);
    }
}
@end

@implementation NSNull (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical {
    return yajl_gen_null(gen);
}
@end

@implementation NSArray (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical {
    yajl_gen_array_open(gen);
    for (id item in self) {
        yajl_gen_status status = [item cbjson_encodeTo: gen canonical: canonical];
        if (status)
            return status;
    }
    return yajl_gen_array_close(gen);
}
@end

@implementation NSDictionary (CBJSONEncoder)
- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen canonical: (BOOL)canonical {
    yajl_gen_map_open(gen);
    id keys;
    if (canonical && self.count > 1) {
        // inlining +orderedKeys: for performance
        keys = [self.allKeys sortedArrayUsingComparator: ^NSComparisonResult(UU id s1, UU id s2) {
            return [s1 compare: s2 options: NSLiteralSearch];
        }];
    } else {
        keys = self;
    }

    for (NSString* key in keys) {
        yajl_gen_status status = [key cbjson_encodeTo: gen canonical: canonical];
        if (status)
            return status;
        status = [self[key] cbjson_encodeTo: gen canonical: canonical];
        if (status)
            return status;
    }
    return yajl_gen_map_close(gen);
}

- (yajl_gen_status) cbjson_encodeTo: (yajl_gen)gen
                          canonical: (BOOL)canonical
                          keyFilter: (CBJSONEncoderKeyFilter)keyFilter
                              error: (NSError**)outError
{
    NSError* error = nil;

    yajl_gen_map_open(gen);
    id keys;
    if (canonical && self.count > 1) {
        // inlining +orderedKeys: for performance
        keys = [self.allKeys sortedArrayUsingComparator: ^NSComparisonResult(id s1, id s2) {
            return [s1 compare: s2 options: NSLiteralSearch];
        }];
    } else {
        keys = self;
    }

    for (NSString* key in keys) {
        if (!keyFilter(key, &error)) {
            if (error) {
                if (outError)
                    *outError = error;
                return -1;
            } else {
                continue;
            }
        }
        yajl_gen_status status = [key cbjson_encodeTo: gen canonical: canonical];
        if (status)
            return status;
        status = [self[key] cbjson_encodeTo: gen canonical: canonical];
        if (status)
            return status;
    }
    return yajl_gen_map_close(gen);
}
@end
