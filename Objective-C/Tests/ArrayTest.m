//
//  ArrayTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

#define kArrayTestDate @"2017-01-01T00:00:00.000Z"
#define kArrayTestBlob @"i'm blob"

@interface ArrayTest : CBLTestCase

@end

@implementation ArrayTest


- (NSArray*) arrayOfAllTypes {
    NSMutableArray* array = [NSMutableArray array];
    [array addObject: @(YES)];
    [array addObject: @(NO)];
    [array addObject: @"string"];
    [array addObject: @(0)];
    [array addObject: @(1)];
    [array addObject: @(-1)];
    [array addObject: @(1.1)];
    [array addObject: [CBLJSON dateWithJSONObject: kArrayTestDate]];
    [array addObject: [NSNull null]];
    
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] init];
    [dict setObject: @"Scott Tiger" forKey: @"name"];
    [array addObject: dict];
    
    CBLMutableArray* subarray = [[CBLMutableArray alloc] init];
    [subarray addValue: @"a"];
    [subarray addValue: @"b"];
    [subarray addValue: @"c"];
    [array addObject: subarray];
    
    // Blob:
    NSData* content = [kArrayTestBlob dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    [array addObject: blob];
    
    return array;
}


- (void) populateData: (CBLMutableArray*)array {
    NSArray* data = [self arrayOfAllTypes];
    for (id o in data) {
        [array addValue: o];
    }
}


- (CBLDocument*) saveArray: (CBLMutableArray*)array
                onDocument: (CBLMutableDocument*)doc
                    forKey: (NSString*)key
                      eval: (void(^)(CBLArray*))block
{
    block(array);
    
    // Set and Save:
    [doc setObject: array forKey: key];
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    // Re-get the document and the array:
    CBLArray* savedArray = [savedDoc arrayForKey: @"array"];
    block(savedArray);
    
    return savedDoc;
}


- (NSString*) blobContent: (CBLBlob*)blob {
    return [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
}


- (void) testCreate {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    AssertEqual(array.count, 0u);
    AssertEqualObjects([array toArray], @[]);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    AssertEqual([doc arrayForKey: @"array"], array);
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([[savedDoc arrayForKey: @"array"] toArray], @[]);
}


- (void) testCreateWithNSArray {
    NSArray* data = @[@"1", @"2", @"3"];
    CBLMutableArray* array = [[CBLMutableArray alloc] initWithArray: data];
    AssertEqual(array.count, data.count);
    AssertEqualObjects([array toArray], data);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    AssertEqual([doc arrayForKey: @"array"], array);
    
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([[savedDoc arrayForKey: @"array"] toArray], data);
}


- (void) testSetNSArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    NSArray* data = @[@"1", @"2", @"3"];
    [array setArray: data];
    
    AssertEqual(array.count, data.count);
    AssertEqualObjects([array toArray], data);
    
    // Save:
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    // Update:
    doc = [savedDoc toMutable];
    array = [doc arrayForKey: @"array"];
    data = @[@"4", @"5", @"6"];
    [array setArray: data];
    
    AssertEqual(array.count, data.count);
    AssertEqualObjects([array toArray], data);
}


- (void) testAddObjects {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    
    // Add objects of all types:
    [self populateData: array];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, 12u);
        AssertEqualObjects([a objectAtIndex: 0], @(YES));
        AssertEqualObjects([a objectAtIndex: 1], @(NO));
        AssertEqualObjects([a objectAtIndex: 2], @"string");
        AssertEqualObjects([a objectAtIndex: 3], @(0));
        AssertEqualObjects([a objectAtIndex: 4], @(1));
        AssertEqualObjects([a objectAtIndex: 5], @(-1));
        AssertEqualObjects([a objectAtIndex: 6], @(1.1));
        AssertEqualObjects([a objectAtIndex: 7], kArrayTestDate);
        AssertEqual([a objectAtIndex: 8], [NSNull null]);
        
        // Dictionary:
        CBLMutableDictionary* subdict = [a objectAtIndex: 9];
        AssertEqualObjects([subdict toDictionary], (@{@"name": @"Scott Tiger"}));
        
        CBLMutableArray* subarray = [a objectAtIndex: 10];
        AssertEqualObjects([subarray toArray], (@[@"a", @"b", @"c"]));
        
        // Blob:
        CBLBlob* blob = [a objectAtIndex: 11];
        AssertEqualObjects([self blobContent: blob], kArrayTestBlob);
    }];
}


- (void) testAddObjectsToExistingArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    
    // Save:
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    doc = [[self saveDocument: doc] toMutable];
    
    // Get an existing array:
    array = [doc arrayForKey: @"array"];
    AssertNotNil(array);
    
    // Update:
    [self populateData: array];
    
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, 24u);
        AssertEqualObjects([a objectAtIndex: 12], @(YES));
        AssertEqualObjects([a objectAtIndex: 13], @(NO));
        AssertEqualObjects([a objectAtIndex: 14], @"string");
        AssertEqualObjects([a objectAtIndex: 15], @(0));
        AssertEqualObjects([a objectAtIndex: 16], @(1));
        AssertEqualObjects([a objectAtIndex: 17], @(-1));
        AssertEqualObjects([a objectAtIndex: 18], @(1.1));
        AssertEqualObjects([a objectAtIndex: 19], kArrayTestDate);
        AssertEqual([a objectAtIndex: 20], [NSNull null]);
        
        // Dictionary:
        CBLMutableDictionary* subdict = [a objectAtIndex: 21];
        AssertEqualObjects([subdict toDictionary], (@{@"name": @"Scott Tiger"}));
        
        CBLMutableArray* subarray = [a objectAtIndex: 22];
        AssertEqualObjects([subarray toArray], (@[@"a", @"b", @"c"]));
        
        // Blob:
        CBLBlob* blob = [a objectAtIndex: 23];
        AssertEqualObjects([self blobContent: blob], kArrayTestBlob);
    }];
}


- (void) testSetObject {
    // Get test data:
    NSArray* data = [self arrayOfAllTypes];
    
    // Prepare CBLMutableArray with NSNull placeholders:
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    for (uint i = 0; i < data.count; i++)
        [array addValue: [NSNull null]];
    
    // Set object at index:
    for (uint i = 0; i < data.count; i++) {
        [array setValue: data[i] atIndex: i];
    }
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, data.count);
        AssertEqualObjects([a objectAtIndex: 0], @(YES));
        AssertEqualObjects([a objectAtIndex: 1], @(NO));
        AssertEqualObjects([a objectAtIndex: 2], @"string");
        AssertEqualObjects([a objectAtIndex: 3], @(0));
        AssertEqualObjects([a objectAtIndex: 4], @(1));
        AssertEqualObjects([a objectAtIndex: 5], @(-1));
        AssertEqualObjects([a objectAtIndex: 6], @(1.1));
        AssertEqualObjects([a objectAtIndex: 7], kArrayTestDate);
        AssertEqual([a objectAtIndex: 8], [NSNull null]);
        
        // Dictionary:
        CBLMutableDictionary* subdict = [a objectAtIndex: 9];
        AssertEqualObjects([subdict toDictionary], (@{@"name": @"Scott Tiger"}));
        
        CBLMutableArray* subarray = [a objectAtIndex: 10];
        AssertEqualObjects([subarray toArray], (@[@"a", @"b", @"c"]));
        
        // Blob:
        CBLBlob* blob = [a objectAtIndex: 11];
        AssertEqualObjects([self blobContent: blob], kArrayTestBlob);
    }];
}


- (void) testSetObjectToExistingArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    doc = [[self saveDocument: doc] toMutable];
    array = [doc arrayForKey: @"array"];

    // Get test data:
    NSArray* data = [self arrayOfAllTypes];
    AssertEqual(array.count, data.count);
    
    // Update: set object (backward) at index:
    for (uint i = 0; i < data.count; i++) {
        [array setValue: data[data.count - i - 1] atIndex: i];
    }
    
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, data.count);
        AssertEqualObjects([a objectAtIndex: 11], @(YES));
        AssertEqualObjects([a objectAtIndex: 10], @(NO));
        AssertEqualObjects([a objectAtIndex: 9], @"string");
        AssertEqualObjects([a objectAtIndex: 8], @(0));
        AssertEqualObjects([a objectAtIndex: 7], @(1));
        AssertEqualObjects([a objectAtIndex: 6], @(-1));
        AssertEqualObjects([a objectAtIndex: 5], @(1.1));
        AssertEqualObjects([a objectAtIndex: 4], kArrayTestDate);
        AssertEqual([a objectAtIndex: 3], [NSNull null]);
        
        // Dictionary:
        CBLMutableDictionary* subdict = [a objectAtIndex: 2];
        AssertEqualObjects([subdict toDictionary], (@{@"name": @"Scott Tiger"}));
        
        CBLMutableArray* subarray = [a objectAtIndex: 1];
        AssertEqualObjects([subarray toArray], (@[@"a", @"b", @"c"]));
        
        // Blob:
        CBLBlob* blob = [a objectAtIndex: 0];
        AssertEqualObjects([self blobContent: blob], kArrayTestBlob);
    }];
}


- (void) testSetObjectOutOfBound {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"a"];
    
    for (id index in @[@(-1), @(1)]) {
        [self expectException: @"NSRangeException" in: ^{
            [array setValue: @"b" atIndex: [index integerValue]];
        }];
    }
}


- (void) testInsertObject {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    
    [array insertValue:@"a" atIndex: 0];
    AssertEqual (array.count, 1u);
    AssertEqualObjects([array objectAtIndex: 0], @"a");
    
    [array insertValue:@"c" atIndex: 0];
    AssertEqual (array.count, 2u);
    AssertEqualObjects([array objectAtIndex: 0], @"c");
    AssertEqualObjects([array objectAtIndex: 1], @"a");
    
    [array insertValue:@"d" atIndex: 1];
    AssertEqual (array.count, 3u);
    AssertEqualObjects([array objectAtIndex: 0], @"c");
    AssertEqualObjects([array objectAtIndex: 1], @"d");
    AssertEqualObjects([array objectAtIndex: 2], @"a");
    
    [array insertValue:@"e" atIndex: 2];
    AssertEqual (array.count, 4u);
    AssertEqualObjects([array objectAtIndex: 0], @"c");
    AssertEqualObjects([array objectAtIndex: 1], @"d");
    AssertEqualObjects([array objectAtIndex: 2], @"e");
    AssertEqualObjects([array objectAtIndex: 3], @"a");
    
    [array insertValue:@"f" atIndex: 4];
    AssertEqual (array.count, 5u);
    AssertEqualObjects([array objectAtIndex: 0], @"c");
    AssertEqualObjects([array objectAtIndex: 1], @"d");
    AssertEqualObjects([array objectAtIndex: 2], @"e");
    AssertEqualObjects([array objectAtIndex: 3], @"a");
    AssertEqualObjects([array objectAtIndex: 4], @"f");
}


- (void) testInsertObjectToExistingArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: [[CBLMutableArray alloc] init] forKey: @"array"];
    doc = [[self saveDocument: doc] toMutable];
    
    CBLMutableArray* array = [doc arrayForKey: @"array"];
    AssertNotNil(array);
    
    [array insertValue:@"a" atIndex: 0];
    doc = [[self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual (a.count, 1u);
        AssertEqualObjects([a objectAtIndex: 0], @"a");
    }] toMutable];
    
    array = [doc arrayForKey: @"array"];
    [array insertValue:@"c" atIndex: 0];
    doc = [[self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual (a.count, 2u);
        AssertEqualObjects([a objectAtIndex: 0], @"c");
        AssertEqualObjects([a objectAtIndex: 1], @"a");
    }] toMutable];
    
    array = [doc arrayForKey: @"array"];
    [array insertValue:@"d" atIndex: 1];
    doc = [[self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual (a.count, 3u);
        AssertEqualObjects([a objectAtIndex: 0], @"c");
        AssertEqualObjects([a objectAtIndex: 1], @"d");
        AssertEqualObjects([a objectAtIndex: 2], @"a");
    }] toMutable];
    
    array = [doc arrayForKey: @"array"];
    [array insertValue:@"e" atIndex: 2];
    doc = [[self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual (a.count, 4u);
        AssertEqualObjects([a objectAtIndex: 0], @"c");
        AssertEqualObjects([a objectAtIndex: 1], @"d");
        AssertEqualObjects([a objectAtIndex: 2], @"e");
        AssertEqualObjects([a objectAtIndex: 3], @"a");
    }] toMutable];
 
    array = [doc arrayForKey: @"array"];
    [array insertValue:@"f" atIndex: 4];
    doc = [[self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual (a.count, 5u);
        AssertEqualObjects([a objectAtIndex: 0], @"c");
        AssertEqualObjects([a objectAtIndex: 1], @"d");
        AssertEqualObjects([a objectAtIndex: 2], @"e");
        AssertEqualObjects([a objectAtIndex: 3], @"a");
        AssertEqualObjects([a objectAtIndex: 4], @"f");
    }] toMutable];
}


- (void) testInsertObjectOutOfBound {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"a"];

    for (id index in @[@(-1), @(2)]) {
        NSInteger i = [index integerValue];
        [self expectException: @"NSRangeException" in: ^{
            [array insertValue: @"b" atIndex: i];
        }];
    }
}


- (void) testRemove {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        [array removeValueAtIndex: i];
    }
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc  forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, 0u);
        AssertEqualObjects([a toArray], (@[]));
    }];
}


- (void) testRemoveExistingArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    doc = [[self saveDocument: doc] toMutable];
    array = [doc arrayForKey: @"array"];
    
    for (NSInteger i = array.count - 1; i >= 0; i--) {
        [array removeValueAtIndex: i];
    }
    
    [self saveArray: array onDocument: doc  forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, 0u);
        AssertEqualObjects([a toArray], (@[]));
    }];
}


- (void) testRemoveOutOfBound {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"a"];
    
    for (id index in @[@(-1), @(1)]) {
        [self expectException: @"NSRangeException" in: ^{
            [array removeValueAtIndex: [index integerValue]];
        }];
    }
}


- (void) testCount {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual(a.count, 12u);
    }];
}


- (void) testGetString {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertNil([a stringAtIndex: 0]);
        AssertNil([a stringAtIndex: 1]);
        AssertEqualObjects([a stringAtIndex: 2], @"string");
        AssertNil([a stringAtIndex: 3]);
        AssertNil([a stringAtIndex: 4]);
        AssertNil([a stringAtIndex: 5]);
        AssertNil([a stringAtIndex: 6]);
        AssertEqualObjects([a stringAtIndex: 7], kArrayTestDate);
        AssertNil([a stringAtIndex: 8]);
        AssertNil([a stringAtIndex: 9]);
        AssertNil([a stringAtIndex: 10]);
        AssertNil([a stringAtIndex: 11]);
    }];
}


- (void) testGetNumber {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqualObjects([a numberAtIndex: 0], @(1));
        AssertEqualObjects([a numberAtIndex: 1], @(0));
        AssertNil([a numberAtIndex: 2]);
        AssertEqualObjects([a numberAtIndex: 3], @(0));
        AssertEqualObjects([a numberAtIndex: 4], @(1));
        AssertEqualObjects([a numberAtIndex: 5], @(-1));
        AssertEqualObjects([a numberAtIndex: 6], @(1.1));
        AssertNil([a numberAtIndex: 7]);
        AssertNil([a numberAtIndex: 8]);
        AssertNil([a numberAtIndex: 9]);
        AssertNil([a numberAtIndex: 10]);
        AssertNil([a numberAtIndex: 11]);
    }];
}


- (void) testGetInteger {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual([a integerAtIndex: 0], 1);
        AssertEqual([a integerAtIndex: 1], 0);
        AssertEqual([a integerAtIndex: 2], 0);
        AssertEqual([a integerAtIndex: 3], 0);
        AssertEqual([a integerAtIndex: 4], 1);
        AssertEqual([a integerAtIndex: 5], -1);
        AssertEqual([a integerAtIndex: 6], 1);
        AssertEqual([a integerAtIndex: 7], 0);
        AssertEqual([a integerAtIndex: 8], 0);
        AssertEqual([a integerAtIndex: 9], 0);
        AssertEqual([a integerAtIndex: 10], 0);
        AssertEqual([a integerAtIndex: 11], 0);
    }];
}


- (void) testGetFloat {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual([a floatAtIndex: 0], 1.0f);
        AssertEqual([a floatAtIndex: 1], 0.0f);
        AssertEqual([a floatAtIndex: 2], 0.0f);
        AssertEqual([a floatAtIndex: 3], 0.0f);
        AssertEqual([a floatAtIndex: 4], 1.0f);
        AssertEqual([a floatAtIndex: 5], -1.0f);
        AssertEqual([a floatAtIndex: 6], 1.1f);
        AssertEqual([a floatAtIndex: 7], 0.0f);
        AssertEqual([a floatAtIndex: 8], 0.0f);
        AssertEqual([a floatAtIndex: 9], 0.0f);
        AssertEqual([a floatAtIndex: 10], 0.0f);
        AssertEqual([a floatAtIndex: 11], 0.0f);
    }];
}


- (void) testGetDouble {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual([a doubleAtIndex: 0], 1.0);
        AssertEqual([a doubleAtIndex: 1], 0.0);
        AssertEqual([a doubleAtIndex: 2], 0.0);
        AssertEqual([a doubleAtIndex: 3], 0.0);
        AssertEqual([a doubleAtIndex: 4], 1.0);
        AssertEqual([a doubleAtIndex: 5], -1.0);
        AssertEqual([a doubleAtIndex: 6], 1.1);
        AssertEqual([a doubleAtIndex: 7], 0.0);
        AssertEqual([a doubleAtIndex: 8], 0.0);
        AssertEqual([a doubleAtIndex: 9], 0.0);
        AssertEqual([a doubleAtIndex: 10], 0.0);
        AssertEqual([a doubleAtIndex: 11], 0.0);
    }];
}


- (void) testSetGetMinMaxNumbers {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @(NSIntegerMin)];
    [array addValue: @(NSIntegerMax)];
    [array addValue: @(FLT_MIN)];
    [array addValue: @(FLT_MAX)];
    [array addValue: @(DBL_MIN)];
    [array addValue: @(DBL_MAX)];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqualObjects([a numberAtIndex: 0], @(NSIntegerMin));
        AssertEqualObjects([a numberAtIndex: 1], @(NSIntegerMax));
        AssertEqualObjects([a objectAtIndex: 0], @(NSIntegerMin));
        AssertEqualObjects([a objectAtIndex: 1], @(NSIntegerMax));
        AssertEqual([a integerAtIndex: 0], NSIntegerMin);
        AssertEqual([a integerAtIndex: 1], NSIntegerMax);
        
        AssertEqualObjects([a numberAtIndex: 2], @(FLT_MIN));
        AssertEqualObjects([a numberAtIndex: 3], @(FLT_MAX));
        AssertEqualObjects([a objectAtIndex: 2], @(FLT_MIN));
        AssertEqualObjects([a objectAtIndex: 3], @(FLT_MAX));
        AssertEqual([a floatAtIndex: 2], FLT_MIN);
        AssertEqual([a floatAtIndex: 3], FLT_MAX);
        
        AssertEqualObjects([a numberAtIndex: 4], @(DBL_MIN));
        AssertEqualObjects([a numberAtIndex: 5], @(DBL_MAX));
        AssertEqualObjects([a objectAtIndex: 4], @(DBL_MIN));
        AssertEqualObjects([a objectAtIndex: 5], @(DBL_MAX));
        AssertEqual([a doubleAtIndex: 4], DBL_MIN);
        AssertEqual([a doubleAtIndex: 5], DBL_MAX);
    }];
}


- (void) testSetGetFloatNumbers {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @(1.00)];
    [array addValue: @(1.49)];
    [array addValue: @(1.50)];
    [array addValue: @(1.51)];
    [array addValue: @(1.99)];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqualObjects([a objectAtIndex: 0], @(1.00));
        AssertEqualObjects([a numberAtIndex: 0], @(1.00));
        AssertEqual([a integerAtIndex: 0], 1);
        AssertEqual([a floatAtIndex: 0], 1.00f);
        AssertEqual([a doubleAtIndex: 0], 1.00);
        
        AssertEqualObjects([a objectAtIndex: 1], @(1.49));
        AssertEqualObjects([a numberAtIndex: 1], @(1.49));
        AssertEqual([a integerAtIndex: 1], 1);
        AssertEqual([a floatAtIndex: 1], 1.49f);
        AssertEqual([a doubleAtIndex: 1], 1.49);
        
        AssertEqualObjects([a objectAtIndex: 2], @(1.50));
        AssertEqualObjects([a numberAtIndex: 2], @(1.50));
        AssertEqual([a integerAtIndex: 2], 1);
        AssertEqual([a floatAtIndex: 2], 1.50f);
        AssertEqual([a doubleAtIndex: 2], 1.50);
        
        AssertEqualObjects([a objectAtIndex: 3], @(1.51));
        AssertEqualObjects([a numberAtIndex: 3], @(1.51));
        AssertEqual([a integerAtIndex: 3], 1);
        AssertEqual([a floatAtIndex: 3], 1.51f);
        AssertEqual([a doubleAtIndex: 3], 1.51);
        
        AssertEqualObjects([a objectAtIndex: 4], @(1.99));
        AssertEqualObjects([a numberAtIndex: 4], @(1.99));
        AssertEqual([a integerAtIndex: 4], 1);
        AssertEqual([a floatAtIndex: 4], 1.99f);
        AssertEqual([a doubleAtIndex: 4], 1.99);
    }];
}


- (void) testGetBoolean {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertEqual([a booleanAtIndex: 0], YES);
        AssertEqual([a booleanAtIndex: 1], NO);
        AssertEqual([a booleanAtIndex: 2], YES);
        AssertEqual([a booleanAtIndex: 3], NO);
        AssertEqual([a booleanAtIndex: 4], YES);
        AssertEqual([a booleanAtIndex: 5], YES);
        AssertEqual([a booleanAtIndex: 6], YES);
        AssertEqual([a booleanAtIndex: 7], YES);
        AssertEqual([a booleanAtIndex: 8], NO);
        AssertEqual([a booleanAtIndex: 9], YES);
        AssertEqual([a booleanAtIndex: 10], YES);
        AssertEqual([a booleanAtIndex: 11], YES);
    }];
}


- (void) testGetDate {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertNil([a dateAtIndex: 0]);
        AssertNil([a dateAtIndex: 1]);
        AssertNil([a dateAtIndex: 2]);
        AssertNil([a dateAtIndex: 3]);
        AssertNil([a dateAtIndex: 4]);
        AssertNil([a dateAtIndex: 5]);
        AssertNil([a dateAtIndex: 6]);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [a dateAtIndex: 7]], kArrayTestDate);
        AssertNil([a dateAtIndex: 8]);
        AssertNil([a dateAtIndex: 9]);
        AssertNil([a dateAtIndex: 10]);
        AssertNil([a dateAtIndex: 11]);
    }];
}


- (void) testGetDictionary {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertNil([a dictionaryAtIndex: 0]);
        AssertNil([a dictionaryAtIndex: 1]);
        AssertNil([a dictionaryAtIndex: 2]);
        AssertNil([a dictionaryAtIndex: 3]);
        AssertNil([a dictionaryAtIndex: 4]);
        AssertNil([a dictionaryAtIndex: 5]);
        AssertNil([a dictionaryAtIndex: 6]);
        AssertNil([a dictionaryAtIndex: 7]);
        AssertNil([a dictionaryAtIndex: 8]);
        AssertEqualObjects([[a dictionaryAtIndex: 9] toDictionary], (@{@"name": @"Scott Tiger"}));
        AssertNil([a dictionaryAtIndex: 10]);
        AssertNil([a dictionaryAtIndex: 11]);
    }];
}


- (void) testGetArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [self populateData: array];
    Assert(array.count == 12);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        AssertNil([a arrayAtIndex: 0]);
        AssertNil([a arrayAtIndex: 1]);
        AssertNil([a arrayAtIndex: 2]);
        AssertNil([a arrayAtIndex: 3]);
        AssertNil([a arrayAtIndex: 4]);
        AssertNil([a arrayAtIndex: 5]);
        AssertNil([a arrayAtIndex: 6]);
        AssertNil([a arrayAtIndex: 7]);
        AssertNil([a arrayAtIndex: 8]);
        AssertNil([a arrayAtIndex: 9]);
        AssertEqualObjects([[a arrayAtIndex: 10] toArray], (@[@"a", @"b", @"c"]));
        AssertNil([a arrayAtIndex: 11]);
    }];
}


- (void) testSetNestedArray {
    CBLMutableArray* array1 = [[CBLMutableArray alloc] init];
    CBLMutableArray* array2 = [[CBLMutableArray alloc] init];
    CBLMutableArray* array3 = [[CBLMutableArray alloc] init];
    
    [array1 addValue: array2];
    [array2 addValue: array3];
    [array3 addValue: @"a"];
    [array3 addValue: @"b"];
    [array3 addValue: @"c"];
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [self saveArray: array1 onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        CBLArray* a1 = a;
        AssertEqual(a1.count, 1u);
        CBLMutableArray* a2 = [a1 objectAtIndex: 0];
        AssertEqual(a2.count, 1u);
        CBLMutableArray* a3 = [a2 objectAtIndex: 0];
        AssertEqual(a3.count, 3u);
        AssertEqualObjects([a3 objectAtIndex: 0], @"a");
        AssertEqualObjects([a3 objectAtIndex: 1], @"b");
        AssertEqualObjects([a3 objectAtIndex: 2], @"c");
    }];
}


- (void) testReplaceArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray* array1 = [[CBLMutableArray alloc] init];
    [array1 addValue: @"a"];
    [array1 addValue: @"b"];
    [array1 addValue: @"c"];
    AssertEqual(array1.count, 3u);
    AssertEqualObjects([array1 toArray], (@[@"a", @"b", @"c"]));
    [doc setObject: array1 forKey: @"array"];
    
    CBLMutableArray* array2 = [[CBLMutableArray alloc] init];
    [array2 addValue: @"x"];
    [array2 addValue: @"y"];
    [array2 addValue: @"z"];
    AssertEqual(array2.count, 3u);
    AssertEqualObjects([array2 toArray], (@[@"x", @"y", @"z"]));
    
    // Replace:
    [doc setObject: array2 forKey: @"array"];
    
    // array1 should be now detached:
    [array1 addValue: @"d"];
    AssertEqual(array1.count, 4u);
    AssertEqualObjects([array1 toArray], (@[@"a", @"b", @"c", @"d"]));
    
    // Check array2:
    AssertEqual(array2.count, 3u);
    AssertEqualObjects([array2 toArray], (@[@"x", @"y", @"z"]));
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    
    // Check current array:
    Assert([savedDoc arrayForKey: @"array"] != array2);
    CBLArray* savedArray = [savedDoc arrayForKey: @"array"];
    AssertEqual(savedArray.count, 3u);
    AssertEqualObjects([savedArray toArray], (@[@"x", @"y", @"z"]));
}


- (void) testReplaceArrayDifferentType {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray* array1 = [[CBLMutableArray alloc] init];
    [array1 addValue: @"a"];
    [array1 addValue: @"b"];
    [array1 addValue: @"c"];
    AssertEqual(array1.count, 3u);
    AssertEqualObjects([array1 toArray], (@[@"a", @"b", @"c"]));
    [doc setObject: array1 forKey: @"array"];
    
    // Replace:
    [doc setObject: @"Daniel Tiger" forKey: @"array"];
    AssertEqualObjects([doc objectForKey: @"array"], @"Daniel Tiger");
    
    // array1 should be now detached:
    [array1 addValue: @"d"];
    AssertEqual(array1.count, 4u);
    AssertEqualObjects([array1 toArray], (@[@"a", @"b", @"c", @"d"]));
    
    // Save:
    CBLDocument* savedDoc = [self saveDocument: doc];
    AssertEqualObjects([savedDoc objectForKey: @"array"], @"Daniel Tiger");
}


- (void) testEnumeratingArray {
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    for (NSInteger i = 0; i < 20; i++) {
        [array addValue: @(i)];
    }
    NSArray* content = [array toArray];
    
    __block NSMutableArray* result = [NSMutableArray array];
    for (NSString* item in array) {
        AssertNotNil(item);
        [result addObject: item];
    }
    AssertEqualObjects(result, content);
    
    // Update:
    [array removeValueAtIndex: 1];
    [array addValue: @(20)];
    [array addValue: @(21)];
    content = [array toArray];
    
    result = [NSMutableArray array];
    for (NSString* item in array) {
        AssertNotNil(item);
        [result addObject: item];
    }
    AssertEqualObjects(result, content);
    
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: array forKey: @"array"];
    
    [self saveArray: array onDocument: doc forKey: @"array" eval: ^(CBLArray* a) {
        result = [NSMutableArray array];
        for (NSString* item in a) {
            AssertNotNil(item);
            [result addObject: item];
        }
        AssertEqualObjects(result, content);
    }];
}


@end
