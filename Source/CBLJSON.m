//
//  CBLJSON.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLJSON.h"


@implementation CBLJSON


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


#pragma mark - DATE CONVERSION:


// These functions are not thread-safe, nor are the NSDateFormatter instances they return.
// Make sure that this function and the formatter are called on only one thread at a time.
static NSDateFormatter* getISO8601Formatter() {
    static NSDateFormatter* sFormatter;
    if (!sFormatter) {
        // Thanks to DenNukem's answer in http://stackoverflow.com/questions/399527/
        sFormatter = [[NSDateFormatter alloc] init];
        sFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
        sFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        sFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        sFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }
    return sFormatter;
}

static NSDateFormatter* getCoarseISO8601Formatter() {
    static NSDateFormatter* sFormatter;
    if (!sFormatter) {
        sFormatter = [[NSDateFormatter alloc] init];
        sFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        sFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        sFormatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        sFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
    }
    return sFormatter;
}


+ (NSString*) JSONObjectWithDate: (NSDate*)date {
    if (!date)
        return nil;
    @synchronized(self) {
        return [getISO8601Formatter() stringFromDate: date];
    }
}

+ (NSDate*) dateWithJSONObject: (id)jsonObject {
    NSString* string = $castIf(NSString, jsonObject);
    if (!string)
        return nil;
    @synchronized(self) {
        return [getISO8601Formatter() dateFromString: string] ?:
                    [getCoarseISO8601Formatter() dateFromString: string];
    }
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
            object = [object objectForKey: key];
            if (!object)
                return nil;
        } else if ([object isKindOfClass: [NSArray class]]) {
            int index;
            if (![scanner scanInt: &index] || index < 0 || index >= (int)[object count])
                return nil;
            object = [object objectAtIndex: index];
        } else {
            return nil;
        }
    }
    return object;
}


@end



#pragma mark - LAZY ARRAY:


@implementation CBLLazyArrayOfJSON

- (instancetype) initWithArray: (NSMutableArray*)array {
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
    id obj = [_array objectAtIndex: index];
    if ([obj isKindOfClass: [NSData class]]) {
        obj = [CBLJSON JSONObjectWithData: obj options: CBLJSONReadingAllowFragments
                                   error: nil];
        [_array replaceObjectAtIndex: index withObject: obj];
    }
    return obj;
}

@end


TestCase(CBLJSON_Date) {
    NSDate* date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33Z"];
    CAssertEq(date.timeIntervalSinceReferenceDate, 386541753.000);
    date = [CBLJSON dateWithJSONObject: @"2013-04-01T20:42:33.388Z"];
    CAssertEq(date.timeIntervalSinceReferenceDate, 386541753.388);
    CAssertEqual([CBLJSON JSONObjectWithDate: date], @"2013-04-01T20:42:33.388Z");
}
