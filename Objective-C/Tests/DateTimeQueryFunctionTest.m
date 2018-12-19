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


- (void) testStringToMillis {
    [self validateStringToMillis: @""
                          result: nil];
    
    [self validateStringToMillis: @"2018-12-32T01:01:01Z"
                          result: nil];
    
    [self validateStringToMillis: @"1970-01-01T00:00:00Z"
                          result: [NSNumber numberWithDouble: 0]];
    
    [self validateStringToMillis: @"1970-01-01T00:00:00.123+0000"
                          result: [NSNumber numberWithDouble: 123]];
    
    [self validateStringToMillis: @"2018-10-23T11:33:01-0700"
                          result: [NSNumber numberWithDouble: 1540319581000]];
    
    [self validateStringToMillis: @"2018-10-23T18:33:01Z"
                          result: [NSNumber numberWithDouble: 1540319581000]];
    
    [self validateStringToMillis: @"2018-10-23T18:33:01.123Z"
                          result: [NSNumber numberWithDouble: 1540319581123]];
    
    // leap year
    [self validateStringToMillis: @"2020-02-29T23:59:59.000000+0000"
                          result: [NSNumber numberWithDouble: 1583020799000]];
}


- (void) testStringToUTC {
    [self validateStringToUTC: nil result: nil];
    [self validateStringToUTC: @"x" result: nil];
    
    [self validateStringToUTC: @"2018-10-23T18:33:01Z"
                       result: @"2018-10-23T18:33:01Z"];
    
    [self validateStringToUTC: @"2018-10-23T11:33:01-0700"
                       result: @"2018-10-23T18:33:01Z"];
    
    [self validateStringToUTC: @"2018-10-23T11:33:01+03:30"
                       result: @"2018-10-23T08:03:01Z"];
    
    [self validateStringToUTC: @"2018-10-23T18:33:01.123Z"
                       result: @"2018-10-23T18:33:01.123Z"];
    
    [self validateStringToUTC: @"2018-10-23T11:33:01.123-0700"
                       result: @"2018-10-23T18:33:01.123Z"];
    
    [self validateStringToUTC: @"1970-01-01T00:00:00.000000+0000"
                       result: @"1970-01-01T00:00:00Z"];
}


- (void) testMillisToString {
    int mSec = 1000;
    double seconds = 0.0;
    [self validateMillisToString: [NSNumber numberWithDouble: seconds * mSec]
                          result: [NSDate dateWithTimeIntervalSince1970: seconds]];
    
    seconds = 0.123;
    [self validateMillisToString: [NSNumber numberWithDouble: seconds * mSec]
                          result: [NSDate dateWithTimeIntervalSince1970: seconds]];
    
    seconds = 1000.123;
    [self validateMillisToString: [NSNumber numberWithDouble: seconds * mSec]
                          result: [NSDate dateWithTimeIntervalSince1970: seconds]];
    
    seconds = 65789245.123;
    [self validateMillisToString: [NSNumber numberWithDouble: seconds * mSec]
                          result: [NSDate dateWithTimeIntervalSince1970: seconds]];
}


- (void) testMillisToUTC {
    [self validateMillisToUTC: [NSNumber numberWithDouble: 0]
                       result: @"1970-01-01T00:00:00Z"];
    
    [self validateMillisToUTC: [NSNumber numberWithDouble: 1540319581000]
                       result: @"2018-10-23T18:33:01Z"];
    
    [self validateMillisToUTC: [NSNumber numberWithDouble: 1540319581123]
                       result: @"2018-10-23T18:33:01.123Z"];
    
    [self validateMillisToUTC: [NSNumber numberWithDouble: 1540319581999]
                       result: @"2018-10-23T18:33:01.999Z"];
}


#pragma mark - Helper Methods


- (void) validateStringToMillis: (NSString*)input result: (nullable NSNumber*)millis {
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: input forKey: key];
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
    AssertEqual([result longLongAtIndex: 0], [millis doubleValue]);
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}


- (void) validateStringToUTC: (nullable NSString*)input result: (nullable NSString*)date {
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setValue: input forKey: key];
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
    AssertEqualObjects([result stringAtIndex: 0], date);
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}


- (void) validateMillisToString: (NSNumber*)input result: (NSDate*)date {
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setDouble: [input doubleValue] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    // convert
    CBLQueryExpression* query = [CBLQueryFunction millisToString: [CBLQueryExpression property: key]];
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


- (void) validateMillisToUTC: (NSNumber*)input result: (NSString*)utcString {
    NSError* error;
    NSString* key = @"dateString";
    CBLMutableDocument* doc = [self createDocument];
    [doc setDouble: [input doubleValue] forKey: key];
    [self saveDocument: doc];
    AssertNil(error);
    
    // convert
    CBLQueryExpression* query = [CBLQueryFunction millisToUTC: [CBLQueryExpression property: key]];
    CBLQuery* q = [CBLQueryBuilder select: @[[CBLQuerySelectResult expression: query]]
                                     from: [CBLQueryDataSource database: self.db]];
    CBLQueryResultSet* rs = [q execute: &error];
    Assert(rs, @"Query failed: %@", error);
    CBLQueryResult* result = [[rs allObjects] firstObject];
    AssertNotNil(result);
    
    // validate
    AssertEqualObjects([result stringAtIndex: 0], utcString);
    
    Assert([self.db purgeDocumentWithID: doc.id error: &error]);
    AssertNil(error);
}


@end
