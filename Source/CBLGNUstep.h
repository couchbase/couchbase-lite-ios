//
//  CBLGNUstep.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#ifdef GNUSTEP

/* Stuff that's in iOS / OS X but not GNUstep or Linux */

#define _GNU_SOURCE

#import <Foundation/Foundation.h>


#ifndef NS_BLOCKS_AVAILABLE
#define NS_BLOCKS_AVAILABLE 1
#endif


typedef int32_t SInt32;
typedef uint32_t UInt32;
typedef int64_t SInt64;
typedef uint64_t UInt64;
typedef int8_t SInt8;
typedef uint8_t UInt8;


// in BSD but not Linux:
int digittoint(int c);


typedef double CFAbsoluteTime;
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);


#define NSRunLoopCommonModes NSDefaultRunLoopMode


typedef NSComparisonResult (^NSComparator)(id obj1, id obj2);

@interface NSArray (GNUstep)
- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr;
@end


@interface NSMutableArray (GNUstep)
- (void)sortUsingComparator:(NSComparator)cmptr;
@end


enum {
    NSDataReadingMappedIfSafe =   1UL << 0,
    NSDataReadingUncached = 1UL << 1,
};
typedef NSUInteger NSDataReadingOptions;

enum {
    NSDataSearchBackwards = 1UL << 0,
    NSDataSearchAnchored = 1UL << 1
};
typedef NSUInteger NSDataSearchOptions;

@interface NSData (GNUstep)
+ (id)dataWithContentsOfFile:(NSString *)path options:(NSDataReadingOptions)readOptionsMask error:(NSError **)errorPtr;
- (NSRange)rangeOfData:(NSData *)dataToFind options:(NSDataSearchOptions)mask range:(NSRange)searchRange;
@end


@interface NSOperationQueue (GNUstep)
- (void)addOperationWithBlock:(void (^)(void))block;
@end


@protocol NSURLConnectionDelegate <NSObject>
@end


@protocol NSStreamDelegate <NSObject>
@end


enum {
    NSURLRequestReloadIgnoringLocalCacheData = NSURLRequestReloadIgnoringCacheData
};


#endif // GNUSTEP
