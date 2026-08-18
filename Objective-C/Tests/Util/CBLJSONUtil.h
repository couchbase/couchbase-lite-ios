//
//  CBLJSONUtil.h
//  CouchbaseLite
//
//  Copyright (c) 2026 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Test-owned JSON utilities. Implemented with Foundation only, independently of
    the product's internal implementation, so that they work in both source and
    binary test targets and don't reuse the code under test. */
@interface CBLJSONUtil : NSObject

/** Formats a date as CouchbaseLite's JSON date representation
    (ISO-8601 with milliseconds, e.g. 2026-08-11T12:34:56.789Z). */
+ (NSString*) jsonDateString: (NSDate*)date;

/** Parses CouchbaseLite's JSON date representation. */
+ (nullable NSDate*) dateFromJSONDateString: (NSString*)string;

/** Parses a JSON string into its Foundation object, for structural comparison
    that is insensitive to key order and whitespace. */
+ (id) jsonObjectFromString: (NSString*)string;

@end

NS_ASSUME_NONNULL_END
