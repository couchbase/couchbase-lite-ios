//
//  JSON_Tests.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/7/15.
//
//

#import "CBLTestCase.h"
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
    date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33+0000"];
    AssertEq(date.timeIntervalSinceReferenceDate, 386541753.000);
    date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33+00:00"];
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

- (void) test_CBJSONEncoder_Filter {
    NSDictionary* input = @{@"foo": @1, @"bar": @2};
    CBJSONEncoder* encoder = [[CBJSONEncoder alloc] init];
    encoder.canonical = YES;
    encoder.keyFilter = ^BOOL(NSString* key, NSError** outError) {
        return ![key isEqualToString: @"bar"];
    };
    Assert([encoder encode: input]);
    AssertEqual([encoder.output my_UTF8ToString], @"{\"foo\":1}");

    encoder = [[CBJSONEncoder alloc] init];
    encoder.canonical = YES;
    encoder.keyFilter = ^BOOL(NSString* key, NSError** outError) {
        if ([key isEqualToString: @"bar"]) {
            *outError = [NSError errorWithDomain: @"Bar" code: 847 userInfo: nil];
            return NO;
        }
        return YES;
    };
    Assert(![encoder encode: input]);
    AssertEqual(encoder.error.domain, @"Bar");
    AssertEq(encoder.error.code, 847);
}


- (void) test_CBJSONEncoderBenchmark {
    id obj = [CBLJSON JSONObjectWithData: [self contentsOfTestFile: @"beer.json"] options: 0 error: NULL];
    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            @autoreleasepool {
                NSError* error;
                Assert([CBJSONEncoder encode: obj error: &error]);
            }
        }
    }];
}

- (void) test_NSJSONEncoderBenchmark {
    id obj = [CBLJSON JSONObjectWithData: [self contentsOfTestFile: @"beer.json"] options: 0 error: NULL];
    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            @autoreleasepool {
                NSError* error;
                Assert([CBLJSON dataWithJSONObject: obj options: 0 error: &error]);
            }
        }
    }];
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
