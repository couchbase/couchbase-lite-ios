//
//  TDJSON.h
//  TouchDB
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>


// Conditional compilation for JSONKit and/or NSJSONSerialization.
// If the app supports OS versions prior to NSJSONSerialization, we'll use JSONKit.
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
#define USE_NSJSON (__IPHONE_OS_VERSION_MIN_REQUIRED >= 50000)
#elif defined(TARGET_OS_MAC)
#define USE_NSJSON (MAC_OS_X_VERSION_MIN_REQUIRED >= 1070)
#elif defined(GNUSTEP)
#define USE_NSJSON 1
#else
#define USE_NSJSON 0
#endif


/** Identical to the corresponding NSJSON option flags. */
enum {
    TDJSONReadingMutableContainers = (1UL << 0),
    TDJSONReadingMutableLeaves = (1UL << 1),
    TDJSONReadingAllowFragments = (1UL << 2)
};
typedef NSUInteger TDJSONReadingOptions;

/** Identical to the corresponding NSJSON option flags. */
enum {
    TDJSONWritingPrettyPrinted = (1UL << 0)
};
typedef NSUInteger TDJSONWritingOptions;


#if USE_NSJSON

#define TDJSON NSJSONSerialization

#else

@interface TDJSON : NSObject

+ (NSData *)dataWithJSONObject:(id)obj
                       options:(TDJSONWritingOptions)opt
                         error:(NSError **)error;

+ (id)JSONObjectWithData:(NSData *)data
                 options:(TDJSONReadingOptions)opt
                   error:(NSError **)error;

@end

#endif // USE_NSJSON
