//
//  CBLGNUstep.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/27/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLGNUstep.h"
#import <Foundation/Foundation.h>


@interface NSError (GNUstep)
+ (NSError*) _last;
@end


int digittoint(int c) {
    if (!isxdigit(c))
        return 0;
    else if (c <= '9')
        return c - '0';
    else if (c <= 'F')
        return 10 + c - 'A';
    else
        return 10 + c - 'a';
}


CFAbsoluteTime CFAbsoluteTimeGetCurrent(void) {
    // NOTE: The time base for this isn't the same as CF's (1970 vs 2001), but this is only being
    // used in CouchbaseLite to calculate relative times, so that doesn't matter.
    return time(NULL);
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
    // TODO: Implement NSDataSearchBackwards
    NSAssert(!(options & NSDataSearchBackwards), @"NSDataSearchBackwards not implemented yet");
    NSUInteger patternLen = dataToFind.length;
    if (patternLen == 0)
        return NSMakeRange(NSNotFound, 0);
    const void* patternBytes = dataToFind.bytes;
    NSUInteger myLen = self.length;
    const void* myBytes = self.bytes;
    const void* start = NULL;
    if (options & NSDataSearchAnchored) {
        if (patternLen <= myLen && memcmp(myBytes, patternBytes, patternLen) == 0)
            start = myBytes;
    } else {
        start = memmem(myBytes, myLen, patternBytes, patternLen);
    }
    if (!start)
        return NSMakeRange(NSNotFound, 0);
    return NSMakeRange(start - myBytes, patternLen);
}

@end


@interface BlockOperation : NSOperation
{
    void (^_blockToRun)(void);
}
@end

@implementation BlockOperation

- (instancetype) initWithBlock: (void (^)(void))block {
    self = [super init];
    if (self)
        _blockToRun = [block copy];
    return self;
}

- (void)main {
    _blockToRun();
}

- (void) dealloc {
    [_blockToRun release];
    [super dealloc];
}

@end


@implementation NSOperationQueue (GNUstep)

- (void)addOperationWithBlock:(void (^)(void))block {
    NSOperation* op = [[BlockOperation alloc] initWithBlock: block];
    [self addOperation: op];
    [op release];
}

@end
