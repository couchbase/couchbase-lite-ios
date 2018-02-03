//
//  CBLJSON.m
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

#import "CBLJSON.h"
#import "CBLParseDate.h"

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

+ (NSString *)stringWithJSONObject:(id)object
                           options:(NSJSONWritingOptions)options
                             error:(NSError **)error
{
    NSData* data = [NSJSONSerialization dataWithJSONObject: object options: options error: error];
    if (!data)
        return nil;
    return [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
}


// These functions are not thread-safe, nor are the NSDateFormatter instances they return.
// Make sure that this function and the formatter are called on only one thread at a time.
static NSDateFormatter* getISO8601Formatter() {
    static NSDateFormatter* sFormatter;
    if (!sFormatter) {
        // Thanks to DenNukem's answer in http://stackoverflow.com/questions/399527/
        sFormatter = [[NSDateFormatter alloc] init];
        sFormatter.dateFormat = @"uuuu-MM-dd'T'HH:mm:ss.SSSXXX";
        sFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
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
    NSString* string = [jsonObject isKindOfClass: NSString.class] ? jsonObject : nil;
    if (!string)
        return NAN;
    return CBLParseISO8601Date(string.UTF8String) + k1970ToReferenceDate;
}


+ (NSDate*) dateWithJSONObject: (id)jsonObject {
    NSTimeInterval t = [self absoluteTimeWithJSONObject: jsonObject];
    return isnan(t) ? nil : [NSDate dateWithTimeIntervalSinceReferenceDate: t];
}


@end
