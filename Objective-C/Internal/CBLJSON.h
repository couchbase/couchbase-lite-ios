//
//  CBLJSON.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Identical to the corresponding NSJSON option flags, with one addition. */
enum {
    CBLJSONWritingPrettyPrinted = (1UL << 0),
    
    CBLJSONWritingAllowFragments = (1UL << 23)  /**< Allows input to be an NSString or NSValue. */
};
typedef NSUInteger CBLJSONWritingOptions;

/** Useful extensions for JSON serialization/parsing. */
@interface CBLJSON : NSJSONSerialization

/** Encodes an NSDate as a string in ISO-8601 format. */
+ (nullable NSString*) JSONObjectWithDate: (nullable NSDate*)date;
+ (nullable NSString*) JSONObjectWithDate: (nullable NSDate*)date timeZone:(NSTimeZone *)tz;

/** Parses an ISO-8601 formatted date string to an NSDate object.
 If the object is not a string, or not valid ISO-8601, or nil, it returns nil. */
+ (nullable NSDate*) dateWithJSONObject: (nullable id)jsonObject;

/** Parses an ISO-8601 formatted date string to an absolute time (timeSinceReferenceDate).
 If the object is not a string, or not valid ISO-8601, or nil, it returns a NAN value. */
+ (CFAbsoluteTime) absoluteTimeWithJSONObject: (nullable id)jsonObject;

/** Encodes an object to a JSON string. */
+ (nullable NSString *)stringWithJSONObject:(id)object
                                    options:(NSJSONWritingOptions)options
                                      error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
