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

@interface DateTimeQueryFunctionTest : CBLTestCase

@end

@implementation DateTimeQueryFunctionTest

#pragma mark - Tests

- (void) testWrongDateFormatStringToMillis {
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

- (void) testWrongDateFormatForStringToUTC {
    NSError* error;
    NSString* prefix = @"invalid";
    CBLMutableDocument* doc = [self createDocument];
    NSUInteger total = [self addInvalidDateStrings: doc prefix: prefix];
    [self saveDocument: doc];
    AssertNil(error);
    
    NSArray* selectQueries = [self getSelectQueryForStringToUTCWithPrefix: prefix
                                                          totalProperties: total];
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    AssertNil(error);
    
    // should be NIL for all the wrong formats
    [self validateAllResultSet: rs withDate: nil propertyCount: total prefix: prefix];
    
}

- (void) testDateWithMilliSeconds {
    NSString* input = @"1970-01-01T02:46:40.123000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

- (void) testDateTillSeconds {
    NSString* input = @"1970-01-01T02:46:40.000000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

- (void) testDateTillMinutes {
    NSString* input = @"1970-01-01T02:46:00.000000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

- (void) testDateWithMidnight {
    NSString* input = @"1970-01-01T00:00:00.000000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

- (void) testDateWithJustBeforeMidnight {
    NSString* input = @"1969-12-31T11:59:59.000000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

- (void) testDateWithLeapYearAndFeb29 {
    NSString* input = @"1920-02-29T11:59:59.000000+0000";
    [self validateBasicStringToMillis: input];
    [self validateStringToMillisWithDifferentTimeZones: input];
    [self validateStringToMillisWithDifferentTimeformat: input];
    
    [self validateBasicStringToUTC: input];
    [self validateStringToUTCWithDifferentTimeZones: input];
    [self validateStringToUTCWithDifferentTimeformat: input];
}

#pragma mark - StringToMillis Helper methods

- (void) validateBasicStringToMillis: (NSString*)input {
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    AssertNotNil(date);
    
    // save
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getISO8601DateStringFromDate: date] forKey: key];
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
    long double dateInMillis = roundl([date timeIntervalSince1970] * 1000);
    AssertEqual([result longLongAtIndex: 0], dateInMillis);
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

- (void) validateStringToMillisWithDifferentTimeZones: (NSString*)input {
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    AssertNotNil(date);
    
    NSString* timezonePrefix = @"tz";
    CBLMutableDocument* doc = [self createDocument];
    [self addDifferentTimezoneDateStringTo: doc forDate: date withPrefix: timezonePrefix];
    [self saveDocument: doc];
    
    NSArray* selectQueries = [self getSelectQueryForStringToMillisWithPrefix: timezonePrefix
                                                             totalProperties: [self timezones].count];
    CBLQuery* q = [CBLQueryBuilder select: selectQueries
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    AssertNil(error);
    
    [self validateResultSet: rs
                 withMillis: round([date timeIntervalSince1970] * 1000)
              propertyCount: [self timezones].count
                     prefix: timezonePrefix];
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

- (void) validateStringToMillisWithDifferentTimeformat: (NSString*)input {
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    AssertNotNil(date);
    
    NSUInteger total = [self dateFormats].count;
    NSString* prefix = @"dateFormat";
    CBLMutableDocument* doc = [self createDocument];
    NSArray* expectedResults = [self addDifferentDateTimeFormatsTo: doc
                                                           forDate: date
                                                        withPrefix: prefix];
    [self saveDocument: doc];
    
    // convert
    NSArray* selectQueries = [self getSelectQueryForStringToMillisWithPrefix: prefix
                                                             totalProperties: total];
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
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", prefix, i];
        double dateInMillis = [[expectedResults objectAtIndex: i] timeIntervalSince1970] * 1000;
        AssertEqual([result longLongForKey: propertyKey], round(dateInMillis));
    }
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

/**
 This method will return the Timezone Query Select results for the StringToMillis
 
 @param propertyPrefix prefix to be added with the propertyKey and the index of the timezone.
 For example, if the prefix is `timezone`, then each properties in the doc will be `timezone-0`,
 `timezone-1`, `timezone-2` etc.
 total total no of properties present, with the prefix.
 @return list of select queries for each timezone date-string.
 */
- (NSArray*) getSelectQueryForStringToMillisWithPrefix: (NSString*)propertyPrefix
                                       totalProperties: (NSUInteger)total {
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < total; i++) {
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", propertyPrefix, i];
        CBLQueryExpression* expr = [CBLQueryFunction
                                    stringToMillis: [CBLQueryExpression property: propertyKey]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expr as: propertyKey]];
    }
    return [NSArray arrayWithArray: selectQueries];
}

#pragma mark - StringToUTC Helper methods

- (void) validateBasicStringToUTC: (NSString*)input {
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    AssertNotNil(date);
    
    // save
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: [self getISO8601DateStringFromDate: date] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    // convert
    CBLQueryExpression* query = [CBLQueryFunction stringToUTC: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // validate
    AssertEqualObjects([result dateAtIndex: 0], date);
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

- (void) validateStringToUTCWithDifferentTimeZones: (NSString*)input {
    NSString* timezonePrefix = @"tz";
    NSUInteger total = [[self timezones] count];
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    CBLMutableDocument* doc = [self createDocument];
    [self addDifferentTimezoneDateStringTo: doc forDate: date withPrefix: timezonePrefix];
    [self saveDocument: doc];
    
    // convert & fetch
    CBLQuery* q = [CBLQueryBuilder select: [self getSelectQueryForStringToUTCWithPrefix: timezonePrefix
                                                                        totalProperties: total]
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    AssertNil(error);
    
    [self validateAllResultSet: rs withDate: date propertyCount: total prefix: timezonePrefix];
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

- (void) validateStringToUTCWithDifferentTimeformat: (NSString*)input {
    NSDate* date = [self getDateFromString: input format: kISO8601DateFormat];
    AssertNotNil(date);
    
    // save
    NSMutableArray* expectedResults = [[NSMutableArray alloc] init];
    NSString* prefix = @"dateformat";
    CBLMutableDocument* doc = [self createDocument];
    [self addDifferentDateTimeFormatsTo: doc forDate: date withPrefix: prefix];
    [self saveDocument: doc];
    
    // convert & fetch
    CBLQuery* q = [CBLQueryBuilder select: [self getSelectQueryForStringToUTCWithPrefix: prefix
                                                                        totalProperties: [[self dateFormats]
                                                                                          count]]
                                     from: [CBLQueryDataSource database: self.db]];
    NSError* error;
    CBLQueryResultSet* rs = [q execute: &error];
    AssertNil(error);
    
    [self validateResultSet: rs expectedResults: expectedResults prefix: prefix];
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}

/**
 This method will return the Timezone Query Select results for the StringToUTC
 
 @param propertyPrefix prefix to be added with the propertyKey and the index of the timezone.
 For example, if the prefix is `timezone`, then each properties in the doc will be `timezone-0`,
 `timezone-1`, `timezone-2` etc.
 total total no of properties present, with the prefix.
 @return list of select queries for each timezone date-string.
 */
- (NSArray*) getSelectQueryForStringToUTCWithPrefix: (NSString*)propertyPrefix
                                    totalProperties: (NSUInteger)total
{
    NSMutableArray* selectQueries = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < total; i++) {
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", propertyPrefix, i];
        CBLQueryExpression* expression = [CBLQueryFunction
                                          stringToUTC: [CBLQueryExpression property: propertyKey]];
        [selectQueries addObject: [CBLQuerySelectResult expression: expression as: propertyKey]];
    }
    return [NSArray arrayWithArray: selectQueries];
}

#pragma mark - Common

#pragma mark Populate Document Methods

/**
 The method will adds invalid date strings to the given document.
 
 @param doc The document where we add the invalid date fields, as properties.
 prefix The prefix of the property key, which will be appended with the index will make the property
 key.
 @return no of invalid properties are added to the docs.
 */
- (NSUInteger) addInvalidDateStrings: (CBLMutableDocument*)doc
                              prefix: (NSString*)prefix
{
    NSDate* now = [NSDate date];
    NSUInteger totalInvalidCases = 0;
    [doc setString: [self getLongStyleDateString: now]
            forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    [doc setString: @""
            forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    [doc setInteger: 9998108
             forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    [doc setString: @"someRandomString"
            forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    // Feb 30th, leap
    [doc setString: @"2020-02-30T01:01:01.000000+0000"
            forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    // Feb 29th, non-leap
    [doc setString: @"2019-02-29T01:01:01.000000+0000"
            forKey: [NSString stringWithFormat: @"%lu", (unsigned long)totalInvalidCases++]];
    return totalInvalidCases;
}

/**
 This method will add date-string for every timezone from [self timezones].
 
 @param
 doc The mutable document where we add all the date strings to.
 date The date whcih needs to be converted to all timezones and added to the document.
 propertyPrefix prefix to be added with the propertyKey and the index of the timezone.
 For example, if the prefix is `timezone`, then each properties in the doc will be `timezone-0`,
 `timezone-1`, `timezone-2` etc.
 
 */
- (void) addDifferentTimezoneDateStringTo: (CBLMutableDocument*)doc
                                  forDate: (NSDate*)date
                               withPrefix: (NSString*)prefix
{
    for (NSUInteger i = 0; i < [self timezones].count; i++) {
        NSTimeZone* tz = [NSTimeZone timeZoneWithAbbreviation: [[self timezones] objectAtIndex: i]];
        NSString* dateString = [self getISO8601DateStringFromDate: date timezone: tz];
        [doc setString: dateString forKey: [NSString stringWithFormat: @"%@-%lu", prefix, i]];
    }
}


/**
 This will add different date time formats as properties of the document supplied.
 
 @param doc The document where we add the new properties.
 date The date which will be converted to different formats.
 prefix The prefix of the property key. It will be appended with the index of the dateFormat array
 will make a property key.
 @return The expected results(NSArray<NSDate>)
 */
- (NSArray<NSDate*>*) addDifferentDateTimeFormatsTo: (CBLMutableDocument*)doc
                                            forDate: (NSDate*)date
                                         withPrefix: (NSString*)prefix
{
    NSMutableArray* expectedResults = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [self dateFormats].count; i++) {
        NSString* format = [[self dateFormats] objectAtIndex: i];
        NSString* dateString = [self getLocalDateStringFromDate: date format: format];
        AssertNotNil(dateString);
        [doc setString: dateString
                forKey: [NSString stringWithFormat: @"%@-%lu", prefix, (unsigned long)i]];
        
        // prepare the expected output date from this
        NSDate* expectedDate = [self getDateFromString: dateString format: format];
        AssertNotNil(expectedDate);
        [expectedResults addObject: expectedDate];
    }
    
    return [NSArray arrayWithArray: expectedResults];
}

#pragma mark Validate Result Set


/**
 The method will validate the result set with the expected results.
 
 @param rs The result set
 expectedResults The expected results to be compared with
 prefix The prefix of the property key, which will be appended with the index will make the property
 key.
 */
- (void) validateResultSet: (CBLQueryResultSet*)rs
           expectedResults: (NSArray*)expectedResults
                    prefix: (NSString*)prefix
{
    Assert(rs);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    for (NSUInteger i = 0; i < expectedResults.count; i++) {
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", prefix, (unsigned long)i];
        AssertEqualObjects([result dateForKey: propertyKey], [expectedResults objectAtIndex: i]);
    }
}

/**
 This method will validate the Query result set with the given date. It will iterate and
 compare
 
 @param rs The result set
 expectedDate The expected result Date to be returned in the result.
 prefix The prefix of the property-key.
 */
- (void) validateAllResultSet: (CBLQueryResultSet*)rs
                     withDate: (nullable NSDate*)expectedDate
                propertyCount: (NSUInteger)count
                       prefix: (NSString*)prefix
{
    Assert(rs);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    for (NSUInteger i = 0; i < count; i++) {
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", prefix, i];
        AssertEqualObjects(expectedDate, [result dateForKey: propertyKey]);
    }
}

/**
 This method will validate the Query result set with the given timestamp. It will iterate and
 compare
 
 @param rs The result set
 timestamp The expected result in milliseconds.
 prefix The prefix of the property-key.
 */
- (void) validateResultSet: (CBLQueryResultSet*)rs
                withMillis: (double)timestamp
             propertyCount: (NSUInteger)count
                    prefix: (NSString*)prefix
{
    Assert(rs);
    NSArray* allResults = [rs allObjects];
    CBLQueryResult* result = [allResults firstObject];
    AssertNotNil(result);
    
    // validate
    for (NSUInteger i = 0; i < count; i++) {
        NSString* propertyKey = [NSString stringWithFormat: @"%@-%lu", prefix, i];
        AssertEqual(timestamp, [result longLongForKey: propertyKey]);
    }
}

#pragma mark Date Conversion methods

- (NSString*) getISO8601DateStringFromDate: (NSDate*)date {
    return [self getISO8601DateStringFromDate: date timezone: [NSTimeZone localTimeZone]];
}

- (NSString*) getISO8601DateStringFromDate: (NSDate*)date timezone: (NSTimeZone*)tz {
    return [self getDateStringFromDate: date
                                format: kISO8601DateFormat
                              timezone: tz];
}

- (NSString*) getLocalDateStringFromDate: (NSDate*)date format: (NSString*)format {
    return [self getDateStringFromDate: date
                                format: format
                              timezone: [NSTimeZone localTimeZone]];
}

- (NSString*) getDateStringFromDate: (NSDate*)date
                             format: (NSString*)format
                           timezone: (NSTimeZone*)tz
{
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

- (NSDate*) getDateFromString: (NSString*)dateString format: (NSString*)format {
    NSDateFormatter* dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat: format];
    return [dateFormatter dateFromString: dateString];
}

#pragma mark - test-constants

- (NSArray*) dateFormats {
    return @[ @"yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ss.SZZZZZ",
              @"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
              @"yyyy-MM-dd'T'HH:mmZZZZZ"];
}

- (NSArray*) timezones {
    return @[ @"BIT", // -12
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

@end
