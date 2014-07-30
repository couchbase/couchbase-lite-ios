//
//  CBLJSON.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSON.h"
#import "CBLParseDate.h"
#import "CBLBase64.h"


@implementation CBLJSON


static NSTimeInterval k1970ToReferenceDate;


+ (void) initialize {
    if (self == [CBLJSON class]) {
        k1970ToReferenceDate = [[NSDate dateWithTimeIntervalSince1970: 0.0]
                                                    timeIntervalSinceReferenceDate];
    }
}


+ (NSData *)dataWithJSONObject:(id)object
                       options:(NSJSONWritingOptions)options
                         error:(NSError **)error
{
    if ((options & CBLJSONWritingAllowFragments)
            && ![object isKindOfClass: [NSDictionary class]]
            && ![object isKindOfClass: [NSArray class]]) {
        // NSJSONSerialization won't write fragments, so if I get one wrap it in an array first:
        object = [[NSArray alloc] initWithObjects: &object count: 1];
        NSData* json = [super dataWithJSONObject: object 
                                         options: (options & ~CBLJSONWritingAllowFragments)
                                           error: NULL];
        return [json subdataWithRange: NSMakeRange(1, json.length - 2)];
    } else {
        return [super dataWithJSONObject: object options: options error: error];
    }
}


+ (NSString*) stringWithJSONObject:(id)obj
                           options:(CBLJSONWritingOptions)opt
                             error:(NSError **)error
{
    return [[self dataWithJSONObject: obj options: opt error: error] my_UTF8ToString];
}


+ (NSData*) appendDictionary: (NSDictionary*)dict
        toJSONDictionaryData: (NSData*)json
{
    if (!dict.count)
        return json;
    NSData* extraJson = [self dataWithJSONObject: dict options: 0 error: NULL];
    if (!extraJson)
        return nil;
    size_t jsonLength = json.length;
    size_t extraLength = extraJson.length;
    CAssert(jsonLength >= 2);
    CAssertEq(*(const char*)json.bytes, '{');
    if (jsonLength == 2)  // Original JSON was empty
        return extraJson;
    NSMutableData* newJson = [NSMutableData dataWithLength: jsonLength + extraLength - 1];
    if (!newJson)
        return nil;
    uint8_t* dst = newJson.mutableBytes;
    memcpy(dst, json.bytes, jsonLength - 1);                          // Copy json w/o trailing '}'
    dst += jsonLength - 1;
    *dst++ = ',';                                                     // Add a ','
    memcpy(dst, (const uint8_t*)extraJson.bytes + 1, extraLength - 1);  // Add "extra" after '{'
    return newJson;
}


#define kObjectOverhead 20

static size_t estimate(id object) {
    if ([object isKindOfClass: [NSString class]]) {
        return kObjectOverhead + 2*[object length];
    } else if ([object isKindOfClass: [NSNumber class]]) {
        return kObjectOverhead + 8;
    } else if ([object isKindOfClass: [NSDictionary class]]) {
        size_t size = kObjectOverhead + sizeof(NSUInteger);
        for (NSString* key in object)
            size += (kObjectOverhead + 2*[key length]) + estimate(object[key]);
        return size;
    } else if ([object isKindOfClass: [NSArray class]]) {
        size_t size = kObjectOverhead + sizeof(NSUInteger);
        for (id item in object)
            size += estimate(item);
        return size;
    } else if ([object isKindOfClass: [NSNull class]]) {
        return kObjectOverhead;
    } else {
        Assert(NO, @"Illegal object type %@ in JSON", [object class]);
    }
}

+ (size_t) estimateMemorySize: (id)object {
    return object ? estimate(object) : 0;
}


#pragma mark - DATE CONVERSION:


// These functions are not thread-safe, nor are the NSDateFormatter instances they return.
// Make sure that this function and the formatter are called on only one thread at a time.
static NSDateFormatter* getISO8601Formatter() {
    static NSDateFormatter* sFormatter;
    if (!sFormatter) {
        // Thanks to DenNukem's answer in http://stackoverflow.com/questions/399527/
        sFormatter = [[NSDateFormatter alloc] init];
        sFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSXXX";
        sFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        sFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }

    return sFormatter;
}

+ (NSString*) JSONObjectWithDate: (NSDate*)date {
    return [self JSONObjectWithDate:date timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
}

+ (NSString*) JSONObjectWithDate: (NSDate*)date timeZone:(NSTimeZone *)tz {
    if (!date)
        return nil;
    @synchronized(self) {
        NSDateFormatter *formatter = getISO8601Formatter();
        formatter.timeZone = tz;
        return [formatter stringFromDate: date];
    }
}

+ (CFAbsoluteTime) absoluteTimeWithJSONObject: (id)jsonObject {
    NSString* string = $castIf(NSString, jsonObject);
    if (!string)
        return NAN;
    return CBLParseISO8601Date(string.UTF8String) + k1970ToReferenceDate;
}

+ (NSDate*) dateWithJSONObject: (id)jsonObject {
    NSTimeInterval t = [self absoluteTimeWithJSONObject: jsonObject];
    return isnan(t) ? nil : [NSDate dateWithTimeIntervalSinceReferenceDate: t];
}


#pragma mark - BASE64:


+ (NSString*) base64StringWithData: (NSData*)data {
    return data ? [CBLBase64 encode: data] : nil;
}

+ (NSData*) dataWithBase64String: (id)jsonObject {
    if (![jsonObject isKindOfClass: [NSString class]])
        return nil;
    return [CBLBase64 decode: jsonObject];
}


#pragma mark - JSON POINTER:


// Resolves a JSON-Pointer string, returning the pointed-to value:
// http://tools.ietf.org/html/draft-ietf-appsawg-json-pointer-04
+ (id) valueAtPointer: (NSString*)pointer inObject: (id)object {
    NSScanner* scanner = [NSScanner scannerWithString: pointer];
    scanner.charactersToBeSkipped = [NSCharacterSet characterSetWithCharactersInString: @"/"];

    while (!scanner.isAtEnd) {
        if ([object isKindOfClass: [NSDictionary class]]) {
            NSString* key;
            if (![scanner scanUpToString: @"/" intoString: &key])
                return nil;
            key = [key stringByReplacingOccurrencesOfString: @"~1" withString: @"/"];
            key = [key stringByReplacingOccurrencesOfString: @"~0" withString: @"~"];
            object = object[key];
            if (!object)
                return nil;
        } else if ([object isKindOfClass: [NSArray class]]) {
            int index;
            if (![scanner scanInt: &index] || index < 0 || index >= (int)[object count])
                return nil;
            object = object[index];
        } else {
            return nil;
        }
    }
    return object;
}


@end



#pragma mark - LAZY ARRAY:


@implementation CBLLazyArrayOfJSON
{
    NSMutableArray* _array;
}

- (instancetype) initWithMutableArray: (NSMutableArray*)array {
    self = [super init];
    if (self) {
        _array = array;
    }
    return self;
}

- (NSUInteger)count {
    return _array.count;
}

- (id)objectAtIndex:(NSUInteger)index {
    id obj = _array[index];
    if ([obj isKindOfClass: [NSData class]]) {
        obj = [CBLJSON JSONObjectWithData: obj options: CBLJSONReadingAllowFragments
                                   error: nil];
        _array[index] = obj;
    }
    return obj;
}

@end



#if DEBUG

TestCase(CBLJSON_Date) {
    AssertAlmostEq([CBLJSON absoluteTimeWithJSONObject: @"2013-04-01T20:42:33Z"], 386541753.000, 1e-6);
    NSDate* date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33Z"];
    CAssertEq(date.timeIntervalSinceReferenceDate, 386541753.000);
    date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33.388Z"];
    AssertAlmostEq(date.timeIntervalSinceReferenceDate, 386541753.388, 1e-6);
    CAssertNil([CBLJSON dateWithJSONObject: @""]);
    CAssertNil([CBLJSON dateWithJSONObject: @"1347554643"]);
    CAssertNil([CBLJSON dateWithJSONObject: @"20:42:33Z"]);

    CAssert(isnan([CBLJSON absoluteTimeWithJSONObject: @""]));

    CAssertEqual([CBLJSON JSONObjectWithDate: date], @"2013-04-01T20:42:33.388Z");

    date = [CBLJSON dateWithJSONObject:@"2014-07-30T17:09:00.000+02:00"];

    CAssertEqual([CBLJSON JSONObjectWithDate:date
                                    timeZone:[NSTimeZone timeZoneForSecondsFromGMT:3600*2]], @"2014-07-30T17:09:00.000+02:00");

    CAssertEqual([CBLJSON JSONObjectWithDate:date
                                    timeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]], @"2014-07-30T15:09:00.000Z");
}


#if 0 // this is a performance not a correctness test; and it's slow
// Benchmark code adapted from https://gist.github.com/AnuragMishra/6474321

#import "sqlite3.h"

static unsigned randomNumberInRange(unsigned start, unsigned end);
static NSString* generateSampleDate();
static NSArray* generateSampleDates(NSUInteger count);
static NSTimeInterval parseDatesUsingCBLParseDate(NSArray* dates);
static NSTimeInterval parseTimesUsingCBLParseDate(NSArray* dates);
static NSTimeInterval parseDatesUsingSQLite(NSArray *dates);
static NSTimeInterval parseDatesUsingNSDateFormatter(NSArray *dates);

TestCase(CBLJSON_Date_Performance) {
    RequireTestCase(CBLJSON_Date);
    const NSUInteger count = 100000;
    NSArray* dates;
    @autoreleasepool {
        dates = generateSampleDates(count);
    }

    NSTimeInterval baselineTime = parseDatesUsingNSDateFormatter(dates);
    Log(@"NSDateFormatter     took %6.2f µsec", baselineTime*1e6);

    NSTimeInterval time = parseDatesUsingSQLite(dates);
    Log(@"sqlite3 strftime    took %6.2f µsec (%.0fx)", time*1e6, baselineTime/time);

    time = parseDatesUsingCBLParseDate(dates);
    Log(@"-dateWithJSONObject took %6.2f µsec (%.0fx)", time*1e6, baselineTime/time);

    time = parseTimesUsingCBLParseDate(dates);
    Log(@"CBLParseDate        took %6.2f µsec (%.0fx)", time*1e6, baselineTime/time);
}

NSArray* generateSampleDates(NSUInteger count)
{
    NSMutableArray *dates = [NSMutableArray array];

    for (NSUInteger i = 0; i < count; i++)
    {
        [dates addObject:generateSampleDate()];
    }

    return dates;
}

NSString* generateSampleDate()
{
    unsigned year = randomNumberInRange(1980, 2013);
    unsigned month = randomNumberInRange(1, 12);
    unsigned date = randomNumberInRange(1, 28);
    unsigned hour = randomNumberInRange(0, 23);
    unsigned minute = randomNumberInRange(0, 59);
    unsigned second = randomNumberInRange(0, 59);
    return [NSString stringWithFormat:@"%u-%02u-%02uT%02u:%02u:%02uZ",
                            year, month, date, hour, minute, second];
}

static NSTimeInterval parseDatesUsingCBLParseDate(NSArray* dates) {
    static const int iterations = 60;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < iterations; i++) {
        for (NSString *dateString in dates) {
            @autoreleasepool {
                (void) [CBLJSON dateWithJSONObject: dateString];
            }
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start)/dates.count/iterations;
}

static NSTimeInterval parseTimesUsingCBLParseDate(NSArray* dates) {
    static const int iterations = 40;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < iterations; i++) {
        for (NSString *dateString in dates) {
            @autoreleasepool {
                (void) [CBLJSON absoluteTimeWithJSONObject: dateString];
            }
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start)/iterations/dates.count;
}

static NSTimeInterval parseDatesUsingSQLite(NSArray *dates)
{
    static const int iterations = 25;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    sqlite3 *db = NULL;
    sqlite3_open(":memory:", &db);

    sqlite3_stmt *statement = NULL;
    sqlite3_prepare_v2(db, "SELECT strftime('%s', ?);", -1, &statement, NULL);

    for (int i = 0; i < iterations; i++) {
        for (NSString *dateString in dates)
        {
            @autoreleasepool {
                sqlite3_bind_text(statement, 1, [dateString UTF8String], -1, SQLITE_STATIC);
                sqlite3_step(statement);
                int64_t value = sqlite3_column_int64(statement, 0);
                (void) [NSDate dateWithTimeIntervalSince1970:value];

                sqlite3_clear_bindings(statement);
                sqlite3_reset(statement);
            }
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start)/dates.count/iterations;
}

static NSTimeInterval parseDatesUsingNSDateFormatter(NSArray *dates)
{
    static const int iterations = 1;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil)
    {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    }

    for (int i = 0; i < iterations; i++) {
        for (NSString *dateString in dates)
        {
            @autoreleasepool {
                (void) [dateFormatter dateFromString:dateString];
            }
        }
    }
    return (CFAbsoluteTimeGetCurrent() - start)/dates.count/iterations;
}

unsigned randomNumberInRange(unsigned start, unsigned end)
{
    unsigned span = end - start;
    return start + (unsigned)arc4random_uniform(span);
}
#endif


#endif // DEBUG
