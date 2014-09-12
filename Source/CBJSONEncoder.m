//
//  CBJSONEncoder.m
//  CBJSON
//
//  Created by Jens Alfke on 12/27/13.
//  Copyright (c) 2013 Couchbase. All rights reserved.
//

#import "CBJSONEncoder.h"
#import "CBLMisc.h"
#include "yajl/yajl_gen.h"


NSString* const CBJSONEncoderErrorDomain = @"CBJSONEncoder";


@implementation CBJSONEncoder
{
    NSMutableData* _encoded;
    yajl_gen _gen;
    yajl_gen_status _status;
}


@synthesize canonical=_canonical;


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
    return [self encodeNestedObject: object];
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
    [self encodedData];
    return _encoded;
}


#define checkStatus(STATUS) ((_status = (STATUS)) == yajl_gen_status_ok)


- (BOOL) encodeNestedObject: (UU id)object {
    if ([object isKindOfClass: [NSString class]]) {
        return [self encodeString: object];
    } else if ([object isKindOfClass: [NSDictionary class]]) {
        return [self encodeDictionary: object];
    } else if ([object isKindOfClass: [NSNumber class]]) {
        return [self encodeNumber: object];
    } else if ([object isKindOfClass: [NSArray class]]) {
        return [self encodeArray: object];
    } else if ([object isKindOfClass: [NSNull class]]) {
        return [self encodeNull];
    } else {
        return NO;
    }
}


- (BOOL) encodeString: (UU NSString*)str {
    __block yajl_gen_status status = yajl_gen_invalid_string;
    CBLWithStringBytes(str, ^(const char *chars, size_t len) {
        status = yajl_gen_string(_gen, (const unsigned char*)chars, len);
    });
    return checkStatus(status);
}


- (BOOL) encodeNumber: (UU NSNumber*)number {
    yajl_gen_status status;
    switch (number.objCType[0]) {
        case 'c': {
            // The only way to tell whether an NSNumber with 'char' type is a boolean is to
            // compare it against the singleton kCFBoolean objects:
            if (number == (id)kCFBooleanTrue)
                status = yajl_gen_bool(_gen, number.boolValue);
            else if (number == (id)kCFBooleanFalse)
                status = yajl_gen_bool(_gen, number.boolValue);
            else
                status = yajl_gen_integer(_gen, number.longLongValue);
            break;
        }
        case 'f':
        case 'd': {
            // Based on yajl_gen_double, except yajl uses too many significant figures (20 not 16)
            // which causes some numbers to round badly (e.g "8.9900000000000002" for "8.99")
            double n = number.doubleValue;
            char str[32];
            if (isnan(n) || isinf(n))  {
                status = yajl_gen_invalid_number;
                break;
            }
            unsigned len = sprintf(str, "%.16g", n);
            if (strspn(str, "0123456789-") == strlen(str)) {
                strcat(str, ".0");
                len += 2;
            }
            status = yajl_gen_number(_gen, str, len);
            //status = yajl_gen_double(_gen, number.doubleValue);
            break;
        }
        case 'Q': {
            char str[32];
            unsigned len = sprintf(str, "%llu", number.unsignedLongLongValue);
            status = yajl_gen_number(_gen, str, len);
            break;
        }
        default:
            status = yajl_gen_integer(_gen, number.longLongValue);
            break;
    }
    return checkStatus(status);
}


- (BOOL) encodeNull {
    return checkStatus(yajl_gen_null(_gen));
}


- (BOOL) encodeArray: (UU NSArray*)array {
    yajl_gen_array_open(_gen);
    for (id item in array)
        if (![self encodeNestedObject: item])
            return NO;
    return checkStatus(yajl_gen_array_close(_gen));
}


- (BOOL) encodeDictionary: (UU NSDictionary*)dict {
    if (!checkStatus(yajl_gen_map_open(_gen)))
        return NO;
    id keys = dict;
    if (_canonical)
        keys = [[self class] orderedKeys: dict];
    for (NSString* key in keys)
        if (![self encodeKey: key value: dict[key]])
            return NO;
    return checkStatus(yajl_gen_map_close(_gen));
}

- (BOOL) encodeKey: (UU id)key value: (UU id)value {
    return [self encodeNestedObject: key] && [self encodeNestedObject: value];
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


- (NSError*) error {
    if (_status == yajl_gen_status_ok)
        return nil;
    return [NSError errorWithDomain: CBJSONEncoderErrorDomain code: _status userInfo: nil];
}


@end



#if DEBUG

static void roundtrip( id obj ) {
    NSData* json = [CBJSONEncoder canonicalEncoding: obj error: nil];
    Log(@"%@ --> `%@`", [obj description], [json my_UTF8ToString]);
    NSError* error;
    id reconstituted = [NSJSONSerialization JSONObjectWithData: json options:NSJSONReadingAllowFragments error: &error];
    CAssert(reconstituted, @"Canonical JSON `%@` was unparseable: %@",
            [json my_UTF8ToString], error);
    CAssertEqual(reconstituted, obj);
}

static void roundtripFloat( double n ) {
    NSData* json = [CBJSONEncoder canonicalEncoding: @(n) error: nil];
    NSError* error;
    id reconstituted = [NSJSONSerialization JSONObjectWithData: json options:NSJSONReadingAllowFragments error: &error];
    CAssert(reconstituted, @"`%@` was unparseable: %@",
            [json my_UTF8ToString], error);
    double delta = [reconstituted doubleValue] / n - 1.0;
    Log(@"%g --> `%@` (error = %g)", n, [json my_UTF8ToString], delta);
    CAssert(fabs(delta) < 1.0e-15, @"`%@` had floating point roundoff error of %g (%g vs %g)",
            [json my_UTF8ToString], delta, [reconstituted doubleValue], n);
}

static NSString* canonicalString(id obj) {
    return [[NSString alloc] initWithData: [CBJSONEncoder canonicalEncoding: obj error: nil]
                                 encoding: NSUTF8StringEncoding];
}

TestCase(CBJSONEncoder_Encoding) {
    CAssertEqual(canonicalString(@YES), @"true");
    CAssertEqual(canonicalString(@NO), @"false");
    CAssertEqual(canonicalString(@1), @"1");
    CAssertEqual(canonicalString(@0), @"0");
    CAssertEqual(canonicalString([NSNumber numberWithChar: 2]), @"2");
    CAssertEqual(canonicalString($null), @"null");
    CAssertEqual(canonicalString(@(3.1)), @"3.1");
}

TestCase(CBJSONEncoder_RoundTrip) {
    roundtrip($true);
    roundtrip($false);
    roundtrip($null);
    
    roundtrip(@0);
    roundtrip(@INT_MAX);
    roundtrip(@INT_MIN);
    roundtrip(@UINT_MAX);
    roundtrip(@INT64_MAX);
    roundtrip(@UINT64_MAX);
    
    roundtripFloat(111111.111111);
    roundtripFloat(M_PI);
    roundtripFloat(6.02e23);
    roundtripFloat(1.23456e-18);
    roundtripFloat(1.0e-37);
    roundtripFloat(UINT_MAX);
    roundtripFloat(UINT64_MAX);
    roundtripFloat(UINT_MAX + 0.01);
    roundtripFloat(1.0e38);
    
    roundtrip(@"");
    roundtrip(@"ordinary string");
    roundtrip(@"\\");
    roundtrip(@"xx\\");
    roundtrip(@"\\xx");
    roundtrip(@"\"\\");
    roundtrip(@"\\.\"");
    roundtrip(@"...\\.\"...");
    roundtrip(@"...\\..\"...");
    roundtrip(@"\r\nHELO\r \tTHER");
    roundtrip(@"\037wow\037");
    roundtrip(@"\001");
    roundtrip(@"\u1234");
    
    roundtrip(@[]);
    roundtrip(@[@[]]);
    roundtrip(@[@"foo", @"bar", $null]);
    
    roundtrip(@{});
    roundtrip(@{@"key": @"value"});
    roundtrip(@{@"\"key\"": $false});
    roundtrip(@{@"\"key\"": $false, @"": @{}});
}

TestCase(CBJSONEncoder_NaNProperty) {
    NSError* error;
    NSData* json = [CBJSONEncoder canonicalEncoding: [NSDecimalNumber notANumber] error: &error];
    CAssert(!json);
    CAssertEqual(error.domain, CBJSONEncoderErrorDomain);
}

#endif
