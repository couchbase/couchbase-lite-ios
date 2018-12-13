//
//  DateTimeQueryFunctionTest.m
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


#import "CBLTestCase.h"

#define kISO8601DateFormat @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
#define kStringToUTCDateFormat @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
#define kMillisToStringFormat @"yyyy-MM-dd'T'HH:mm:ss.SSSZ"

@interface DateTimeQueryFunctionTest : CBLTestCase

@end

@implementation DateTimeQueryFunctionTest

#pragma mark - StringToMillis

- (void) testStringToMillis {
    // save
    NSError* error;
    NSDate* now = [NSDate date];
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getISO8601DateString: now] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    // convert
    CBLQueryExpression* query = [CBLQueryFunction stringToMillis: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // validate
    long double nowInMillis = roundl([now timeIntervalSince1970] * 1000);
    AssertEqual([result longLongAtIndex: 0], nowInMillis);
}

- (void) testWrongDateFormat {
    NSError* error;
    NSDate* now = [NSDate date];
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getLongStyleDateString: now] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    CBLQueryExpression* query = [CBLQueryFunction stringToMillis: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // should be nil
    AssertNil([result valueAtIndex: 0]);
}

- (void) testStringToMillisWithDifferentTimeZones {
    // save
    NSDate* now = [NSDate date];
    CBLMutableDocument* doc = [self createDocument];
    for (NSString* abbr in [self timezones]) {
        NSString* dateString =
            [self getISO8601DateString: now timezone: [NSTimeZone timeZoneWithAbbreviation:abbr]];
        [doc setString: dateString forKey: abbr];
    }
    [self saveDocument: doc];
    
    // convert
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSString* abbr in [self timezones]) {
        CBLQueryExpression* expression =
            [CBLQueryFunction stringToMillis: [CBLQueryExpression property: abbr]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expression as: abbr]];
    }
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs);
    AssertNil(error);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    long double nowInMillis = roundl([now timeIntervalSince1970] * 1000);
    for (NSString* abbr in [self timezones]) {
        AssertEqual(nowInMillis, [result longLongForKey: abbr]);
    }
}

- (void) testStringToMillisWithDifferentTimeformat {
    NSDate* now = [NSDate date];
    CBLMutableDocument* doc = [self createDocument];
    NSMutableArray* expectedResults = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [self dateFormats].count; i++) {
        // save
        NSString* format = [[self dateFormats] objectAtIndex: i];
        NSString* dateString = [self getLocalDateString: now format: format];
        [doc setString: dateString forKey: [NSString stringWithFormat: @"%lu", (unsigned long)i]];
        
        // create expected outputs from the input
        NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat: format];
        NSDate* date = [dateFormatter dateFromString: dateString];
        [expectedResults addObject: [NSNumber numberWithDouble: [date timeIntervalSince1970]]];
    }
    [self saveDocument: doc];
    
    // convert
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [self dateFormats].count; i++) {
        NSString* key = [NSString stringWithFormat: @"%lu", (unsigned long)i];
        CBLQueryExpression* expression =
            [CBLQueryFunction stringToMillis: [CBLQueryExpression property: key]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expression as: key]];
    }
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs);
    AssertNil(error);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    for (NSUInteger i = 0; i < expectedResults.count; i++) {
        NSString* key = [NSString stringWithFormat: @"%lu", (unsigned long)i];
        double expectedResult = [[expectedResults objectAtIndex: i] doubleValue] * 1000;
        AssertEqual([result longLongForKey: key], expectedResult);
    }
}

#pragma mark - StringToUTC

- (void) testWrongDateFormatWithStringToUTC {
    NSError* error;
    NSDate* now = [NSDate date];
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getLongStyleDateString: now] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    CBLQueryExpression* query = [CBLQueryFunction stringToUTC: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // should be NIL
    AssertNil([result valueAtIndex: 0]);
}

- (void) testStringToUTCWithDifferentTimeZones {
    NSDate* now = [NSDate date];
    CBLMutableDocument* doc = [self createDocument];
    for (NSString* abbr in [self timezones]) {
        NSString* dateString = [self getISO8601DateString: now
                                                 timezone: [NSTimeZone
                                                            timeZoneWithAbbreviation: abbr]];
        [doc setString: dateString forKey: abbr];
    }
    [self saveDocument: doc];
    
    // convert & fetch
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSString* abbr in [self timezones]) {
        CBLQueryExpression* expression =
        [CBLQueryFunction stringToUTC: [CBLQueryExpression property: abbr]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expression as: abbr]];
    }
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs);
    AssertNil(error);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    NSString* expectedOutput = [self getUTCDateString: now format: kStringToUTCDateFormat];
    for (NSString* abbr in [self timezones]) {
        AssertEqualObjects(expectedOutput, [result stringForKey: abbr]);
    }
}

- (void) testStringToUTCWithDifferentTimeformat {
    NSString* input = @"1970-01-01T02:46:40.123000Z";
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat: kStringToUTCDateFormat];
    NSDate* date = [dateFormatter dateFromString: input];
    
    // save
    CBLMutableDocument* doc = [self createDocument];
    for (NSUInteger i = 0; i < [self dateFormats].count; i++) {
        NSString* format = [[self dateFormats] objectAtIndex: i];
        NSString* dateString = [self getLocalDateString: date format: format];
        [doc setString: dateString forKey: [NSString stringWithFormat: @"%lu", (unsigned long)i]];
    }
    [self saveDocument: doc];
    
    // convert & fetch
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [self dateFormats].count; i++) {
        NSString* key = [NSString stringWithFormat: @"%lu", (unsigned long)i];
        CBLQueryExpression* expression =
        [CBLQueryFunction stringToUTC: [CBLQueryExpression property: key]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expression as: key]];
    }
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs);
    AssertNil(error);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    NSArray* expectedResults = [[NSArray alloc] initWithObjects:
                                @"1970-01-01T02:46:40.123Z",
                                @"1970-01-01T02:46:40.123Z",
                                @"1970-01-01T02:46:40.100Z",
                                @"1970-01-01T02:46:40Z",
                                @"1970-01-01T02:46:00Z", nil];
    for (NSUInteger i = 0; i < expectedResults.count; i++) {
        NSString* key = [NSString stringWithFormat: @"%lu", (unsigned long)i];
        AssertEqualObjects([result stringForKey: key], [expectedResults objectAtIndex: i]);
    }
}

#pragma mark - MillisToString

- (void) testWrongDataWithMillisToString {
    // save
    NSError* error;
    NSDate* now = [NSDate date];
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getISO8601DateString: now] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    // convert & fetch
    CBLQueryExpression* query = [CBLQueryFunction millisToString: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // should be NIL
    AssertNil([result valueAtIndex: 0]);
}

- (void) testMillisToString {
    NSError* error;
    NSString* key = @"dateString";
    NSDate* date = [NSDate dateWithTimeIntervalSince1970: 10000.123456];
    NSTimeInterval dateInMillis = [date timeIntervalSince1970] * 1000;
    CBLMutableDocument* doc = [self createDocument];
    [doc setDouble: dateInMillis forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    // convert & fetch
    CBLQueryExpression* query = [CBLQueryFunction millisToString: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // validate
    NSString* dateString = [self getLocalDateString: date format: kMillisToStringFormat];
    AssertEqualObjects(dateString, [result valueAtIndex: 0]);
}

#pragma mark - Helper Methods

- (NSString*) getISO8601DateString: (NSDate*)date {
    return [self getISO8601DateString: date
                             timezone: [NSTimeZone localTimeZone]];
}

- (NSString*) getISO8601DateString: (NSDate*)date timezone: (NSTimeZone*)tz {
    return [self getDateString: date
                        format: kISO8601DateFormat
                      timezone: tz];
}

- (NSString*) getLocalDateString: (NSDate*)date format: (NSString*)format {
    return [self getDateString: date
                        format: format
                      timezone: [NSTimeZone localTimeZone]];
}

- (NSString*) getUTCDateString: (NSDate*)date format: (NSString*)format {
    return [self getDateString: date
                        format: format
                      timezone: [NSTimeZone timeZoneWithName: @"UTC"]];
}

- (NSString*) getDateString: (NSDate*)date format: (NSString*)format timezone: (NSTimeZone*)tz {
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeZone: tz];
    [dateFormatter setDateFormat: format];
    return [dateFormatter stringFromDate: date];
}

- (NSString*) getLongStyleDateString: (NSDate*)date {
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle: NSDateFormatterLongStyle];
    return [dateFormatter stringFromDate: date];
}

- (NSArray*) timezones {
    return  @[ @"BIT", // -12
               @"AKST", // -9
               @"CDT", // -6
               @"IST", // -5:30
               @"EDT", // -4
               @"UYT", // -3
               @"EGT", // -1
               @"UTC", // +00
               @"BST", // +1
               @"CAT", // +2
               @"MSK", // +3
               @"MUT", // +4
               @"MST", // +5
               @"PST", // +8
               @"JST", // +9
               @"ACDT"]; // +10:30
}

- (NSArray*) dateFormats {
    return @[ @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ss.SZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
              @"yyyy-MM-dd'T'HH:mmZZZZZ"];
}

@end
