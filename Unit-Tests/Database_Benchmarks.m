//
//  Database_Benchmarks.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 3/17/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBLTestCase.h"


@interface Database_Benchmarks : CBLTestCaseWithDB
@end


@implementation Database_Benchmarks
{
    NSMutableArray *s_names;
    NSRange _ageRange;
}


// This stuff is adapted from Realm's benchmark code

static const int kNumTestNames = 1000;

- (void) setUp {
    [super setUp];
    s_names = [NSMutableArray arrayWithCapacity:kNumTestNames];
    for (int i = 0; i < kNumTestNames; i++) {
        [s_names addObject:[NSString stringWithFormat:@"Foo%i", i]];
    }
    _ageRange = NSMakeRange(20, 50);
}

- (int)ageValue:(NSUInteger)row {
    return row % (int)_ageRange.length + (int)_ageRange.location;
}

- (BOOL)hiredValue:(NSUInteger)row {
    return row % 2;
}

- (NSString *)nameValue:(NSUInteger)row {
    return s_names[row % kNumTestNames];
}


- (void)insertObject:(NSUInteger)index {
    @autoreleasepool {
        CBLDocument* doc = [db createDocument];
        NSDictionary* properties = @{@"type":  @"employee",
                                     @"name":  [self nameValue:index],
                                     @"age":   @([self ageValue:index]),
                                     @"hired": @([self hiredValue:index])};
        NSError* error;
        Assert([doc putProperties: properties error: &error]);
    }
}


- (void)testCreateNewDocs {
    static const NSUInteger kNumDocs = 50000;

    NSTimeInterval start = CFAbsoluteTimeGetCurrent();
    __block NSTimeInterval lastReport = start;
    [db inTransaction:^BOOL{
        for (NSUInteger i=0; i < kNumDocs; i++) {
            [self insertObject: i];
            if ((i+1) % 1000 == 0) {
                NSTimeInterval now = CFAbsoluteTimeGetCurrent();
                Log(@"%6u\t%.3f\t%6.0f", (unsigned)i+1, now - lastReport, 1000/(now - lastReport));
                lastReport = now;
            }
        }
        return YES;
    }];

    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    Log(@"COMMIT\t%.3f\t%.3f", now - lastReport, now - start);

    NSTimeInterval duration = CFAbsoluteTimeGetCurrent() - start;
    Log(@"testCreateNewDocs took %.3f sec; that's %.0f docs/sec", duration, kNumDocs/duration);
}

@end
