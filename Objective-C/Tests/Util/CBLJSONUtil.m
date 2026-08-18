//
//  CBLJSONUtil.m
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

#import "CBLJSONUtil.h"

@implementation CBLJSONUtil

static NSDateFormatter* jsonDateFormatter(void) {
    static NSDateFormatter* sFormatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sFormatter = [[NSDateFormatter alloc] init];
        sFormatter.dateFormat = @"uuuu-MM-dd'T'HH:mm:ss.SSSXXX";
        sFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier: NSCalendarIdentifierGregorian];
        sFormatter.locale = [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"];
        sFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];
    });
    return sFormatter;
}

+ (NSString*) jsonDateString: (NSDate*)date {
    return [jsonDateFormatter() stringFromDate: date];
}

+ (NSDate*) dateFromJSONDateString: (NSString*)string {
    return [jsonDateFormatter() dateFromString: string];
}

+ (id) jsonObjectFromString: (NSString*)string {
    NSData* data = [string dataUsingEncoding: NSUTF8StringEncoding];
    NSError* error;
    id object = [NSJSONSerialization JSONObjectWithData: data options: 0 error: &error];
    NSCAssert(!error, @"Invalid JSON: %@", error);
    return object;
}

@end
