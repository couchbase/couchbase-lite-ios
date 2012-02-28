//
//  TDGNUstep.m
//  TouchDB
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDGNUstep.h"
#import <Foundation/Foundation.h>


@interface NSError (GNUstep)
+ (NSError*) _last;
@end



int digittoint(int c) {
    if (isdigit(c))
        return c - '0';
    else if (c >= 'A' && c <= 'F')
        return 10 + c - 'A';
    else if (c >= 'a' && c <= 'f')
        return 10 + c - 'a';
    else
        return 0;
}



static NSComparisonResult callComparator(id a, id b, void* context) {
    return ((NSComparator)context)(a, b);
}

@implementation NSArray (GNUstep)

- (NSArray *)sortedArrayUsingComparator:(NSComparator)cmptr {
    return [self sortedArrayUsingFunction: &callComparator context: cmptr];
}

@end

@implementation NSMutableArray (GNUstep)

- (void)sortUsingComparator:(NSComparator)cmptr {
    [self sortUsingFunction: &callComparator context: cmptr];
}

@end



@implementation NSData (GNUstep)

+ (id)dataWithContentsOfFile:(NSString *)path
                     options:(NSDataReadingOptions)options
                       error:(NSError **)errorPtr
{
    NSData* data;
    if (options & NSDataReadingMappedIfSafe)
        data = [self dataWithContentsOfMappedFile: path];
    else
        data = [self dataWithContentsOfFile: path];
    if (!data && errorPtr)
        *errorPtr = [NSError _last];
    return data;
}

- (NSRange)rangeOfData:(NSData *)dataToFind
               options:(NSDataSearchOptions)options
                 range:(NSRange)searchRange
{
    NSParameterAssert(dataToFind);
    NSParameterAssert(options == 0); // not implemented yet
    const void* myBytes = self.bytes;
    NSUInteger patternLen = dataToFind.length;
    if (patternLen == 0)
        return NSMakeRange(NSNotFound, 0);
    const void* start = memmem(myBytes, self.length, dataToFind.bytes, patternLen);
    if (!start)
        return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(start - myBytes, patternLen);
}

@end
