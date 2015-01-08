//
//  JSON_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/7/15.
//
//

#import "CBLTestCase.h"
#import "CBLCollateJSON.h"
#import "CBLJSON.h"
#import "CBJSONEncoder.h"
#import "CBLJSONReader.h"


@interface CBL_GenericObjectMatcher : CBLJSONMatcher
@property Class arrayMatcherClass;
@property Class dictMatcherClass;
@end


@interface JSON_Tests : CBLTestCase
@end


@implementation JSON_Tests


- (void) test_CBLJSON_Date {
    XCTAssertEqualWithAccuracy([CBLJSON absoluteTimeWithJSONObject: @"2013-04-01T20:42:33Z"], 386541753.000, 1e-6);
    NSDate* date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33Z"];
    AssertEq(date.timeIntervalSinceReferenceDate, 386541753.000);
    date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33.388Z"];
    XCTAssertEqualWithAccuracy(date.timeIntervalSinceReferenceDate, 386541753.388, 1e-6);
    AssertNil([CBLJSON dateWithJSONObject: @""]);
    AssertNil([CBLJSON dateWithJSONObject: @"1347554643"]);
    AssertNil([CBLJSON dateWithJSONObject: @"20:42:33Z"]);

    Assert(isnan([CBLJSON absoluteTimeWithJSONObject: @""]));

    AssertEqual([CBLJSON JSONObjectWithDate: date], @"2013-04-01T20:42:33.388Z");

    date = [CBLJSON dateWithJSONObject:@"2014-07-30T17:09:00.000+02:00"];

    AssertEqual([CBLJSON JSONObjectWithDate:date
                                    timeZone:[NSTimeZone timeZoneForSecondsFromGMT:3600*2]], @"2014-07-30T17:09:00.000+02:00");

    AssertEqual([CBLJSON JSONObjectWithDate:date
                                    timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]], @"2014-07-30T15:09:00.000Z");
}


#pragma mark - JSON ENCODER


- (void) roundtrip: (id)obj {
    NSData* json = [CBJSONEncoder canonicalEncoding: obj error: nil];
    Log(@"%@ --> `%@`", [obj description], [json my_UTF8ToString]);
    NSError* error;
    id reconstituted = [NSJSONSerialization JSONObjectWithData: json options:NSJSONReadingAllowFragments error: &error];
    Assert(reconstituted, @"Canonical JSON `%@` was unparseable: %@",
            [json my_UTF8ToString], error);
    AssertEqual(reconstituted, obj);
}

- (void) roundtripFloat: (double)n {
    NSData* json = [CBJSONEncoder canonicalEncoding: @(n) error: nil];
    NSError* error;
    id reconstituted = [NSJSONSerialization JSONObjectWithData: json options:NSJSONReadingAllowFragments error: &error];
    Assert(reconstituted, @"`%@` was unparseable: %@",
            [json my_UTF8ToString], error);
    double delta = [reconstituted doubleValue] / n - 1.0;
    Log(@"%g --> `%@` (error = %g)", n, [json my_UTF8ToString], delta);
    Assert(fabs(delta) < 1.0e-15, @"`%@` had floating point roundoff error of %g (%g vs %g)",
            [json my_UTF8ToString], delta, [reconstituted doubleValue], n);
}

static NSString* canonicalString(id obj) {
    return [[NSString alloc] initWithData: [CBJSONEncoder canonicalEncoding: obj error: nil]
                                 encoding: NSUTF8StringEncoding];
}

- (void) test_CBJSONEncoder_Encoding {
    AssertEqual(canonicalString(@YES), @"true");
    AssertEqual(canonicalString(@NO), @"false");
    AssertEqual(canonicalString(@1), @"1");
    AssertEqual(canonicalString(@0), @"0");
    AssertEqual(canonicalString([NSNumber numberWithChar: 2]), @"2");
    AssertEqual(canonicalString($null), @"null");
    AssertEqual(canonicalString(@(3.1)), @"3.1");
}


- (void) test_CBJSONEncoder_RoundTrip {
    [self roundtrip: $true];
    [self roundtrip: $false];
    [self roundtrip: $null];
    
    [self roundtrip: @0];
    [self roundtrip: @INT_MAX];
    [self roundtrip: @INT_MIN];
    [self roundtrip: @UINT_MAX];
    [self roundtrip: @INT64_MAX];
    [self roundtrip: @UINT64_MAX];
    
    [self roundtripFloat: 111111.111111];
    [self roundtripFloat: M_PI];
    [self roundtripFloat: 6.02e23];
    [self roundtripFloat: 1.23456e-18];
    [self roundtripFloat: 1.0e-37];
    [self roundtripFloat: UINT_MAX];
    [self roundtripFloat: UINT64_MAX];
    [self roundtripFloat: UINT_MAX + 0.01];
    [self roundtripFloat: 1.0e38];
    
    [self roundtrip: @""];
    [self roundtrip: @"ordinary string"];
    [self roundtrip: @"\\"];
    [self roundtrip: @"xx\\"];
    [self roundtrip: @"\\xx"];
    [self roundtrip: @"\"\\"];
    [self roundtrip: @"\\.\""];
    [self roundtrip: @"...\\.\"..."];
    [self roundtrip: @"...\\..\"..."];
    [self roundtrip: @"\r\nHELO\r \tTHER"];
    [self roundtrip: @"\037wow\037"];
    [self roundtrip: @"\001"];
    [self roundtrip: @"\u1234"];
    
    [self roundtrip: @[]];
    [self roundtrip: @[@[]]];
    [self roundtrip: @[@"foo", @"bar", $null]];
    
    [self roundtrip: @{}];
    [self roundtrip: @{@"key": @"value"}];
    [self roundtrip: @{@"\"key\"": $false}];
    [self roundtrip: @{@"\"key\"": $false, @"": @{}}];
}

- (void) test_CBJSONEncoder_NaNProperty {
    NSError* error;
    NSData* json = [CBJSONEncoder canonicalEncoding: [NSDecimalNumber notANumber] error: &error];
    Assert(!json);
    AssertEqual(error.domain, CBJSONEncoderErrorDomain);
}


#pragma mark - JSON COLLATOR


// encodes an object to a C string in JSON format. JSON fragments are allowed.
static const char* encode(id obj) {
    NSString* str = [CBLJSON stringWithJSONObject: obj
                                         options: CBLJSONWritingAllowFragments error: NULL];
    NSCAssert(str, @"Not encodable");
    return [str UTF8String];
}


static int collateLimited(void *mode, const void * str1, const void * str2, unsigned arrayLimit) {
    // Be evil and put numeric garbage past the ends of str1 and str2 (see bug #138):
    size_t len1 = strlen(str1), len2 = strlen(str2);
    char buf1[len1 + 3], buf2[len2 + 3];
    strlcpy(buf1, str1, sizeof(buf1));
    strlcat(buf1, "99", sizeof(buf1));
    strlcpy(buf2, str2, sizeof(buf2));
    strlcat(buf2, "88", sizeof(buf2));
    return CBLCollateJSONLimited(mode, (int)len1, buf1, (int)len2, buf2, arrayLimit);
}

static int collate(void *mode, const void * str1, const void * str2) {
    return collateLimited(mode, str1, str2, UINT_MAX);
}

- (void) test_CBLCollateScalars {
    RequireTestCase(CBLCollateConvertEscape);
    void* mode = kCBLCollateJSON_Unicode;
    AssertEq(collate(mode, "true", "false"), 1);
    AssertEq(collate(mode, "false", "true"), -1);
    AssertEq(collate(mode, "null", "17"), -1);
    AssertEq(collate(mode, "1", "1"), 0);
    AssertEq(collate(mode, "123", "1"), 1);
    AssertEq(collate(mode, "123", "0123.0"), 0);
    AssertEq(collate(mode, "123", "\"123\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"123\""), 1);
    AssertEq(collate(mode, "\"123\"", "\"1234\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"1235\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"1234\""), 0);
    AssertEq(collate(mode, "\"12\\/34\"", "\"12/34\""), 0);
    AssertEq(collate(mode, "\"\\/1234\"", "\"/1234\""), 0);
    AssertEq(collate(mode, "\"1234\\/\"", "\"1234/\""), 0);
    // Test long numbers, case where readNumber has to malloc a buffer:
    AssertEq(collate(mode, "123", "00000000000000000000000000000000000000000000000000123"), 0);
#ifndef GNUSTEP     // FIXME: GNUstep doesn't support Unicode collation yet
    AssertEq(collate(mode, "\"a\"", "\"A\""), -1);
    AssertEq(collate(mode, "\"A\"", "\"aa\""), -1);
    AssertEq(collate(mode, "\"B\"", "\"aa\""), 1);
    AssertEq(collate(mode, "\"~\"", "\"A\""), -1);
    AssertEq(collate(mode, "\"_\"", "\"A\""), -1);
#endif
}

- (void) test_CBLCollateASCII {
    RequireTestCase(CBLCollateConvertEscape);
    void* mode = kCBLCollateJSON_ASCII;
    AssertEq(collate(mode, "true", "false"), 1);
    AssertEq(collate(mode, "false", "true"), -1);
    AssertEq(collate(mode, "null", "17"), -1);
    AssertEq(collate(mode, "123", "1"), 1);
    AssertEq(collate(mode, "123", "0123.0"), 0);
    AssertEq(collate(mode, "123", "\"123\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"123\""), 1);
    AssertEq(collate(mode, "\"123\"", "\"1234\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"1235\""), -1);
    AssertEq(collate(mode, "\"1234\"", "\"1234\""), 0);
    AssertEq(collate(mode, "\"12\\/34\"", "\"12/34\""), 0);
    AssertEq(collate(mode, "\"12/34\"", "\"12\\/34\""), 0);
    AssertEq(collate(mode, "\"\\/1234\"", "\"/1234\""), 0);
    AssertEq(collate(mode, "\"1234\\/\"", "\"1234/\""), 0);
    AssertEq(collate(mode, "\"A\"", "\"a\""), -1);
    AssertEq(collate(mode, "\"B\"", "\"a\""), -1);
}

- (void) test_CBLCollateRaw {
    void* mode = kCBLCollateJSON_Raw;
    AssertEq(collate(mode, "false", "17"), 1);
    AssertEq(collate(mode, "false", "true"), -1);
    AssertEq(collate(mode, "null", "true"), -1);
    AssertEq(collate(mode, "[\"A\"]", "\"A\""), -1);
    AssertEq(collate(mode, "\"A\"", "\"a\""), -1);
    AssertEq(collate(mode, "[\"b\"]", "[\"b\",\"c\",\"a\"]"), -1);
}

- (void) test_CBLCollateArrays {
    void* mode = kCBLCollateJSON_Unicode;
    AssertEq(collate(mode, "[]", "\"foo\""), 1);
    AssertEq(collate(mode, "[]", "[]"), 0);
    AssertEq(collate(mode, "[true]", "[true]"), 0);
    AssertEq(collate(mode, "[false]", "[null]"), 1);
    AssertEq(collate(mode, "[]", "[null]"), -1);
    AssertEq(collate(mode, "[123]", "[45]"), 1);
    AssertEq(collate(mode, "[123]", "[45,67]"), 1);
    AssertEq(collate(mode, "[123.4,\"wow\"]", "[123.40,789]"), 1);
    AssertEq(collate(mode, "[5,\"wow\"]", "[5,\"wow\"]"), 0);
    AssertEq(collate(mode, "[5,\"wow\"]", "1"), 1);
    AssertEq(collate(mode, "1", "[5,\"wow\"]"), -1);
}

- (void) test_CBLCollateNestedArrays {
    void* mode = kCBLCollateJSON_Unicode;
    AssertEq(collate(mode, "[[]]", "[]"), 1);
    AssertEq(collate(mode, "[1,[2,3],4]", "[1,[2,3.1],4,5,6]"), -1);
}

- (void) test_CBLCollateUnicodeStrings {
    // Make sure that CBLJSON never creates escape sequences we can't parse.
    // That includes "\unnnn" for non-ASCII chars, and "\t", "\b", etc.
    RequireTestCase(CBLCollateConvertEscape);
    void* mode = kCBLCollateJSON_Unicode;
    AssertEq(collate(mode, encode(@"fréd"), encode(@"fréd")), 0);
    AssertEq(collate(mode, encode(@"ømø"), encode(@"omo")), 1);
    AssertEq(collate(mode, encode(@"\t"), encode(@" ")), -1);
    AssertEq(collate(mode, encode(@"\001"), encode(@" ")), -1);
}

- (void) test_CBLCollateLimited {
    void* mode = kCBLCollateJSON_Unicode;
    AssertEq(collateLimited(mode, "[5,\"wow\"]", "[4,\"wow\"]", 1), 1);
    AssertEq(collateLimited(mode, "[5,\"wow\"]", "[5,\"wow\"]", 1), 0);
    AssertEq(collateLimited(mode, "[5,\"wow\"]", "[5,\"MOM\"]", 1), 0);
    AssertEq(collateLimited(mode, "[5,\"wow\"]", "[5]", 1), 0);
    AssertEq(collateLimited(mode, "[5,\"wow\"]", "[5,\"MOM\"]", 2), 1);
}


#pragma mark - JSON READER


- (void) test_CBLJSONMatcher_Object {
    NSString* const kJSON = @"{\"foo\": 1, \"bar\": 2}";

    CBL_GenericObjectMatcher* matcher = [[CBL_GenericObjectMatcher alloc] init];

    CBLJSONReader* parser = [[CBLJSONReader alloc] initWithMatcher: matcher];
    Assert([parser parseData: [kJSON dataUsingEncoding: NSUTF8StringEncoding]]);
    Assert([parser finish]);
    AssertEqual([matcher end], (@{@"foo": @1, @"bar": @2}));
}


@end




@interface CBLGenericArrayMatcher : CBLJSONArrayMatcher // implemented in CBLJSONReader.m
@end

@interface CBLGenericDictMatcher : CBLJSONDictMatcher // implemented in CBLJSONReader.m
@end


@implementation CBL_GenericObjectMatcher
{
    id _value;
    Class _arrayMatcherClass, _dictMatcherClass;
}

@synthesize arrayMatcherClass = _arrayMatcherClass;
@synthesize dictMatcherClass = _dictMatcherClass;

- (id)init
{
    self = [super init];
    if (self) {
        _arrayMatcherClass = [CBLGenericArrayMatcher class];
        _dictMatcherClass = [CBLGenericDictMatcher class];
    }
    return self;
}

- (bool) matchValue: (id)value {
    NSAssert(!_value, @"value already set");
    _value = value;
    return true;
}

- (CBLJSONArrayMatcher*) startArray {
    return [[_arrayMatcherClass alloc] init];
}

- (CBLJSONDictMatcher*) startDictionary {
    return [[_dictMatcherClass alloc] init];
}

- (id) end {
    return _value;
}

@end
