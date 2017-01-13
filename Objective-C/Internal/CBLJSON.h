//
//  CBLJSON.h
//  CouchbaseLite
//
//  Source: https://github.com/couchbase/couchbase-lite-ios/blob/master/Source/API/CBLJSON.h
//  Created by Jens Alfke on 2/27/12.
//
//  Created by Pasin Suriyentrakorn on 1/4/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
+ (NSString*) JSONObjectWithDate: (NSDate*)date;
+ (NSString*) JSONObjectWithDate: (NSDate*)date timeZone:(NSTimeZone *)tz;

/** Parses an ISO-8601 formatted date string to an NSDate object.
 If the object is not a string, or not valid ISO-8601, or nil, it returns nil. */
+ (nullable NSDate*) dateWithJSONObject: (nullable id)jsonObject;

/** Parses an ISO-8601 formatted date string to an absolute time (timeSinceReferenceDate).
 If the object is not a string, or not valid ISO-8601, or nil, it returns a NAN value. */
+ (CFAbsoluteTime) absoluteTimeWithJSONObject: (nullable id)jsonObject;


@end

NS_ASSUME_NONNULL_END
