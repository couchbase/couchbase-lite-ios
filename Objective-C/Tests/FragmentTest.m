//
//  FragmentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

@interface CBLFragmentTest : CBLTestCase
@end


// See: https://github.com/couchbaselabs/couchbase-lite-apiv2/wiki/FragmentTest

@implementation CBLFragmentTest

- (void) testGetDocFragmentWithID{
    // TODO: DocumentFragment is not implemented
}

- (void) testGetDocFragmentWithNonExistingID{
    // TODO: DocumentFragment is not implemented
}

// test SubDocument
- (void) testGetFragmentFromSubdocValue {
    // data
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    // new doc
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    CBLFragment* fragment;
    
    // pre-save check
    // SubDocument Fragment
    fragment = doc[@"address"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string); // string
    AssertNil(fragment.number); // number
    AssertNil(fragment.date);   // date
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(FALSE, fragment.boolValue); // boolean
    AssertNil(fragment.array);          // array
    AssertNotNil(fragment.object);      // object
    AssertNotNil(fragment.value);       // value
    AssertEqual(fragment.subdocument, fragment.object);
    AssertEqual(fragment.subdocument, fragment.value);
    AssertNotNil(fragment.subdocument); // subdocument
    AssertEqualObjects([fragment.subdocument toDictionary], dict[@"address"]);
    AssertEqual(2, (int)[[fragment.subdocument toDictionary] count]);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"address"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string); // string
    AssertNil(fragment.number); // number
    AssertNil(fragment.date);   // date
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(FALSE, fragment.boolValue); // boolean
    AssertNil(fragment.array);          // array
    AssertNotNil(fragment.object);      // object
    AssertNotNil(fragment.value);       // value
    AssertEqual(fragment.subdocument, fragment.object);
    AssertEqual(fragment.subdocument, fragment.value);
    AssertNotNil(fragment.subdocument); // subdocument
    AssertEqualObjects([fragment.subdocument toDictionary], dict[@"address"]);
    AssertEqual(2, (int)[[fragment.subdocument toDictionary] count]);
}

// array fragment
- (void)testGetFragmentFromArrayValue{
    NSDictionary* dict = @{@"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]};
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary:dict];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"references"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string); // string
    AssertNil(fragment.number); // number
    AssertNil(fragment.date);   // date
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(FALSE, fragment.boolValue); // boolean
    AssertNil(fragment.subdocument); // subdocument
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqual(fragment.array, fragment.object);
    AssertEqual(fragment.array, fragment.value);
    AssertNotNil(fragment.array); // array
    AssertEqualObjects([fragment.array toArray],dict[@"references"]);
    AssertEqual(2, (int)[fragment.array toArray].count);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"references"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    
    AssertNil(fragment.string); // string
    AssertNil(fragment.number); // number
    AssertNil(fragment.date);   // date
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(FALSE, fragment.boolValue); // boolean
    AssertNil(fragment.subdocument); // subdocument
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqual(fragment.array, fragment.object);
    AssertEqual(fragment.array, fragment.value);
    AssertNotNil(fragment.array); // array
    AssertEqualObjects([fragment.array toArray],dict[@"references"]);
    AssertEqual(2, (int)[fragment.array toArray].count);
}

// get all types of fragments from integer
- (void)testGetFragmentFromInteger{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@10 forKey:@"integer"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"integer"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNotNil(fragment.number);   // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@10, fragment.number);
    AssertEqual(10, fragment.integerValue); // integer
    XCTAssertEqualWithAccuracy(10.0, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(10.0, fragment.doubleValue, 0.0001); // double
    AssertEqual(true, fragment.boolValue);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // pre-save check
    fragment = doc[@"integer"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNotNil(fragment.number);   // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@10, fragment.number);
    AssertEqual(10, fragment.integerValue); // integer
    XCTAssertEqualWithAccuracy(10.0, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(10.0, fragment.doubleValue, 0.0001); // double
    AssertEqual(true, fragment.boolValue);
}

// get all types of fragments from float
- (void)testGetFragmentFromFloat{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@100.10 forKey:@"float"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"float"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);     // string
    AssertNil(fragment.date);       // date
    AssertNil(fragment.subdocument);// subdocument
    AssertNil(fragment.array);      // array
    AssertNotNil(fragment.number);  // number
    AssertNotNil(fragment.object);  // object
    AssertNotNil(fragment.value);   // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@100.10, fragment.number);
    AssertEqual(100, fragment.integerValue);   // integer
    XCTAssertEqualWithAccuracy(100.10, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(100.10, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                           // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"float"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);     // string
    AssertNil(fragment.date);       // date
    AssertNil(fragment.subdocument);// subdocument
    AssertNil(fragment.array);      // array
    AssertNotNil(fragment.number);  // number
    AssertNotNil(fragment.object);  // object
    AssertNotNil(fragment.value);   // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@100.10, fragment.number);
    AssertEqual(100, fragment.integerValue);   // integer
    XCTAssertEqualWithAccuracy(100.10, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(100.10, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                           // boolean
}

// get all types of fragments from double
- (void)testGetFragmentFromDouble{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@99.99 forKey:@"double"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"double"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNotNil(fragment.number);   // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@99.99, fragment.number);
    AssertEqual(99, fragment.integerValue);  // integer
    XCTAssertEqualWithAccuracy(99.99, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(99.99, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                          // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"double"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNotNil(fragment.number);   // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@99.99, fragment.number);
    AssertEqual(99, fragment.integerValue);  // integer
    XCTAssertEqualWithAccuracy(99.99, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(99.99, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                          // boolean
}

// get all types of fragments from boolean
- (void)testGetFragmentFromBoolean{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@true forKey:@"boolean"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"boolean"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);     // string
    AssertNil(fragment.date);       // date
    AssertNil(fragment.subdocument);// subdocument
    AssertNil(fragment.array);      // array
    AssertNotNil(fragment.number);  // number
    AssertNotNil(fragment.object);  // object
    AssertNotNil(fragment.value);   // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@1, fragment.number);
    AssertEqual(1, fragment.integerValue);    // integer
    XCTAssertEqualWithAccuracy(1.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(1.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                         // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"boolean"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);     // string
    AssertNil(fragment.date);       // date
    AssertNil(fragment.subdocument);// subdocument
    AssertNil(fragment.array);      // array
    AssertNotNil(fragment.number);  // number
    AssertNotNil(fragment.object);  // object
    AssertNotNil(fragment.value);   // value
    AssertEqualObjects(fragment.number, fragment.object);
    AssertEqualObjects(fragment.number, fragment.value);
    AssertEqualObjects(@1, fragment.number);
    AssertEqual(1, fragment.integerValue);    // integer
    XCTAssertEqualWithAccuracy(1.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(1.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(true, fragment.boolValue);                         // boolean
}

// get all types of fragments from date
- (void)testGetFragmentFromDate{
    NSDate* date = [NSDate date];
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:date forKey:@"date"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"date"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNotNil(fragment.string);   // string
    AssertNotNil(fragment.date);     // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNil(fragment.number);      // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.object);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.value);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], [CBLJSON JSONObjectWithDate: date]);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate], [fragment.date timeIntervalSinceReferenceDate], 0.001);
    AssertEqual(0, fragment.integerValue);   // integer
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);                         // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"date"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNotNil(fragment.string);   // string
    AssertNotNil(fragment.date);     // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNil(fragment.number);      // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.object);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.value);
    AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], [CBLJSON JSONObjectWithDate: date]);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate], [fragment.date timeIntervalSinceReferenceDate], 0.001);
    AssertEqual(0, fragment.integerValue);   // integer
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);                         // boolean
}

// get all types of fragments from String
- (void)testGetFragmentFromString{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@"hello world" forKey:@"string"];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"string"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNotNil(fragment.string);   // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNil(fragment.number);      // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.string, fragment.object);
    AssertEqualObjects(fragment.string, fragment.value);
    AssertEqualObjects(@"hello world", fragment.string);
    AssertEqual(0, fragment.integerValue);    // integer
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);   // boolean                     // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"string"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNotNil(fragment.string);   // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.array);       // array
    AssertNil(fragment.number);      // number
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertEqualObjects(fragment.string, fragment.object);
    AssertEqualObjects(fragment.string, fragment.value);
    AssertEqualObjects(@"hello world", fragment.string);
    AssertEqual(0, fragment.integerValue);    // integer
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);   // boolean
}

// nested subdocument fragment
- (void) testGetNestedSubdocFragment {
    // data
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    // new doc
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"address"][@"phones"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);  // string
    AssertNil(fragment.date);    // date
    AssertNil(fragment.array);   // array
    AssertEqual(0, fragment.integerValue);  // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);   // boolean
    AssertNotNil(fragment.subdocument); // subdocument
    AssertNotNil(fragment.object);      // object
    AssertNotNil(fragment.value);       // value
    AssertEqual(fragment.subdocument, fragment.object);
    AssertEqual(fragment.subdocument, fragment.value);
    AssertEqualObjects([fragment.subdocument toDictionary], dict[@"address"][@"phones"]);
    AssertEqual(1, (int)[[fragment.subdocument toDictionary] count]);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"address"][@"phones"];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);  // string
    AssertNil(fragment.date);    // date
    AssertNil(fragment.array);   // array
    AssertEqual(0, fragment.integerValue);  // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);   // boolean
    AssertNotNil(fragment.subdocument); // subdocument
    AssertNotNil(fragment.object);      // object
    AssertNotNil(fragment.value);       // value
    AssertEqual(fragment.subdocument, fragment.object);
    AssertEqual(fragment.subdocument, fragment.value);
    AssertEqualObjects([fragment.subdocument toDictionary], dict[@"address"][@"phones"]);
    AssertEqual(1, (int)[[fragment.subdocument toDictionary] count]);
}

// not existing subdocument fragment
- (void) testGetNestedNonExistingSubdocumentFragment {
    // data
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    // new doc
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary: dict];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"address"][@"country"];
    AssertNotNil(fragment);
    AssertFalse(fragment.exists);
    AssertNil(fragment.string);            // string
    AssertNil(fragment.date);              // date
    AssertNil(fragment.array);             // array
    AssertNil(fragment.subdocument);       // subdocument
    AssertNil(fragment.object);            // object
    AssertNil(fragment.value);             // value
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);// boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"address"][@"country"];
    AssertNotNil(fragment);
    AssertFalse(fragment.exists);
    AssertNil(fragment.string);            // string
    AssertNil(fragment.date);              // date
    AssertNil(fragment.array);             // array
    AssertNil(fragment.subdocument);       // subdocument
    AssertNil(fragment.object);            // object
    AssertNil(fragment.value);             // value
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001); // float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001); // double
    AssertEqual(false, fragment.boolValue);// boolean
}

- (void)testGetNestedArrayFragments{
    NSDictionary* dict = @{@"nested-array": @[@[@1,@2,@3], @[@4,@5,@6]]};
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary:dict];
    CBLFragment* fragment;
    
    // pre-save check
    fragment = doc[@"nested-array"][1];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(false, fragment.boolValue);// boolean
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertNotNil(fragment.array);    // array
    AssertEqual(fragment.array, fragment.object);
    AssertEqual(fragment.array, fragment.value);
    AssertEqualObjects([fragment.array toArray],dict[@"nested-array"][1]);
    AssertEqual(3, (int)[fragment.array toArray].count);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"nested-array"][1];
    AssertNotNil(fragment);
    Assert(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertEqual(0, fragment.integerValue); // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(false, fragment.boolValue);// boolean
    AssertNotNil(fragment.object);   // object
    AssertNotNil(fragment.value);    // value
    AssertNotNil(fragment.array);    // array
    AssertEqual(fragment.array, fragment.object);
    AssertEqual(fragment.array, fragment.value);
    AssertEqualObjects([fragment.array toArray],dict[@"nested-array"][1]);
    AssertEqual(3, (int)[fragment.array toArray].count);
}

// non existing array fragment
- (void) testGetNestedNonExistingArrayFragments{
    NSDictionary* dict = @{@"nested-array": @[@[@1,@2,@3], @[@4,@5,@6]]};
    
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1" dictionary:dict];
    CBLFragment* fragment;
    // pre-save check
    fragment = doc[@"nested-array"][2];
    AssertNotNil(fragment);
    AssertFalse(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.object);      // object
    AssertNil(fragment.value);       // value
    AssertNil(fragment.array);       // array
    AssertEqual(0, fragment.integerValue);  // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(false, fragment.boolValue); // boolean
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    fragment = doc[@"nested-array"][2];
    AssertNotNil(fragment);
    AssertFalse(fragment.exists);
    AssertNil(fragment.string);      // string
    AssertNil(fragment.date);        // date
    AssertNil(fragment.subdocument); // subdocument
    AssertNil(fragment.object);      // object
    AssertNil(fragment.value);       // value
    AssertNil(fragment.array);       // array
    AssertEqual(0, fragment.integerValue);  // int
    XCTAssertEqualWithAccuracy(0.00, fragment.floatValue,  0.0001);// float
    XCTAssertEqualWithAccuracy(0.00, fragment.doubleValue, 0.0001);// double
    AssertEqual(false, fragment.boolValue); // boolean
}

- (void)testSubdocFragmentSet{
    NSDate* date = [NSDate date];
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"string"].value = @"value";
    doc[@"bool"].value = @true;
    doc[@"int"].value = @7;
    doc[@"float"].value = @2.2f;
    doc[@"double"].value = @3.3;
    doc[@"date"].value = date;
    
    AssertEqualObjects(@"value", doc[@"string"].string);
    AssertEqual(true, doc[@"bool"].boolValue);
    AssertEqual(7, doc[@"int"].integerValue);
    AssertEqual(2.2f, doc[@"float"].floatValue);
    AssertEqual(3.3, doc[@"double"].doubleValue);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate], [doc[@"date"].date timeIntervalSinceReferenceDate], 0.001);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects(@"value", doc[@"string"].string);
    AssertEqual(true, doc[@"bool"].boolValue);
    AssertEqual(7, doc[@"int"].integerValue);
    AssertEqual(2.2f, doc[@"float"].floatValue);
    AssertEqual(3.3, doc[@"double"].doubleValue);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate], [doc[@"date"].date timeIntervalSinceReferenceDate], 0.001);
}

- (void)testSubdocFragmentSetSubdocument{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLSubdocument *subdoc = [[CBLSubdocument alloc] init];
    [subdoc setObject:@"Jason" forKey:@"name"];
    [subdoc setObject:@{@"street": @"1 Star Way.",@"phones": @{@"mobile": @"650-123-4567"}}  forKey:@"address"];
    doc[@"subdoc"].value = subdoc;
    
    AssertEqualObjects(doc[@"subdoc"][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"subdoc"][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"subdoc"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects(doc[@"subdoc"][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"subdoc"][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"subdoc"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

- (void)testSubdocFragmentSetArrayObject{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    CBLArray *array = [[CBLArray alloc] init];
    [array setArray:@[@0, @1, @2]];
    doc[@"array"].value = array;
    
    AssertNil(doc[@"array"][-1].number);
    AssertFalse(doc[@"array"][-1].exists);
    AssertEqualObjects(@0, doc[@"array"][0].number);
    AssertEqualObjects(@1, doc[@"array"][1].number);
    AssertEqualObjects(@2, doc[@"array"][2].number);
    AssertNil(doc[@"array"][3].number);
    AssertFalse(doc[@"array"][3].exists);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertNil(doc[@"array"][-1].number);
    AssertFalse(doc[@"array"][-1].exists);
    AssertEqualObjects(@0, doc[@"array"][0].number);
    AssertEqualObjects(@1, doc[@"array"][1].number);
    AssertEqualObjects(@2, doc[@"array"][2].number);
    AssertNil(doc[@"array"][3].number);
    AssertFalse(doc[@"array"][3].exists);
}

- (void)testSubdocFragmentSetDictionary{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"dict"].value = @{ @"name": @"Jason",
                            @"address": @{
                                    @"street": @"1 Star Way.",
                                    @"phones": @{@"mobile": @"650-123-4567"}}};
    
    AssertEqualObjects(doc[@"dict"][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"dict"][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"dict"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertEqualObjects(doc[@"dict"][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"dict"][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"dict"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

- (void)testSubdocFragmentSetArray{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"dict"].value = @{};
    doc[@"dict"][@"array"].value = @[@0, @1, @2];
    
    AssertNil(doc[@"dict"][@"array"][-1].number);
    AssertFalse(doc[@"dict"][@"array"][-1].exists);
    AssertEqualObjects(@0, doc[@"dict"][@"array"][0].number);
    AssertEqualObjects(@1, doc[@"dict"][@"array"][1].number);
    AssertEqualObjects(@2, doc[@"dict"][@"array"][2].number);
    AssertNil(doc[@"dict"][@"array"][3].number);
    AssertFalse(doc[@"dict"][@"array"][3].exists);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertNil(doc[@"dict"][@"array"][-1].number);
    AssertFalse(doc[@"dict"][@"array"][-1].exists);
    AssertEqualObjects(@0, doc[@"dict"][@"array"][0].number);
    AssertEqualObjects(@1, doc[@"dict"][@"array"][1].number);
    AssertEqualObjects(@2, doc[@"dict"][@"array"][2].number);
    AssertNil(doc[@"dict"][@"array"][3].number);
    AssertFalse(doc[@"dict"][@"array"][3].exists);
}

- (void)testNonSubdocFragmentSetObject{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setObject:@"value1" forKey:@"string1"];
    [doc setObject:@"value2" forKey:@"string2"];
    
    // pre-save check
    doc[@"string1"].value = @10;
    AssertEqualObjects(@10, doc[@"string1"].value);
    AssertEqualObjects(@"value2", doc[@"string2"].value);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post-save check
    doc[@"string2"].value = @100;
    AssertEqualObjects(@10,  doc[@"string1"].value);
    AssertEqualObjects(@100, doc[@"string2"].value);
}

- (void)testArrayFragmentSet{
    NSDate* date = [NSDate date];
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    
    // pre-save check
    [doc[@"array"].array addObject:@"string"];
    [doc[@"array"].array addObject:@10];
    [doc[@"array"].array addObject:@10.10];
    [doc[@"array"].array addObject:@true];
    [doc[@"array"].array addObject:date];
    
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    for(int i = 0; i < 5; i++){
        AssertNotNil(doc[@"array"][i]);
        Assert(doc[@"array"][i].exists);
    }
    AssertNotNil(doc[@"array"][5]);
    AssertFalse(doc[@"array"][5].exists);
    
    AssertEqualObjects(@"string", doc[@"array"][0].value);
    AssertEqualObjects(@10, doc[@"array"][1].value);
    AssertEqualObjects(@10.10, doc[@"array"][2].value);
    AssertEqualObjects(@true, doc[@"array"][3].value);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate],
                               [doc[@"array"][4].date timeIntervalSinceReferenceDate],
                               0.001);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    for(int i = 0; i < 5; i++){
        AssertNotNil(doc[@"array"][i]);
        Assert(doc[@"array"][i].exists);
    }
    AssertNotNil(doc[@"array"][5]);
    AssertFalse(doc[@"array"][5].exists);
    
    AssertEqualObjects(@"string", doc[@"array"][0].value);
    AssertEqualObjects(@10, doc[@"array"][1].value);
    AssertEqualObjects(@10.10, doc[@"array"][2].value);
    AssertEqualObjects(@true, doc[@"array"][3].value);
    XCTAssertEqualWithAccuracy([date timeIntervalSinceReferenceDate],
                               [doc[@"array"][4].date timeIntervalSinceReferenceDate],
                               0.001);
}

- (void)testArrayFragmentSetSubdocument{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    CBLSubdocument *subdoc = [[CBLSubdocument alloc] init];
    [subdoc setObject:@"Jason" forKey:@"name"];
    [subdoc setObject:@{@"street": @"1 Star Way.",@"phones": @{@"mobile": @"650-123-4567"}}  forKey:@"address"];
    [doc[@"array"].array addObject:subdoc];
    
    // pre-save check
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    AssertNotNil(doc[@"array"][0]);
    Assert(doc[@"array"][0].exists);
    AssertNotNil(doc[@"array"][1]);
    AssertFalse(doc[@"array"][1].exists);
    
    AssertEqualObjects(doc[@"array"][0][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    AssertNotNil(doc[@"array"][0]);
    Assert(doc[@"array"][0].exists);
    AssertNotNil(doc[@"array"][1]);
    AssertFalse(doc[@"array"][1].exists);
    
    AssertEqualObjects(doc[@"array"][0][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

- (void) testArrayFragmentSetDictionary{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@{@"name":@"Jason", @"address":@{@"street": @"1 Star Way.",@"phones": @{@"mobile": @"650-123-4567"}}}];
    
    // pre-save check
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    AssertNotNil(doc[@"array"][0]);
    Assert(doc[@"array"][0].exists);
    AssertNotNil(doc[@"array"][1]);
    AssertFalse(doc[@"array"][1].exists);
    
    AssertEqualObjects(doc[@"array"][0][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertNotNil(doc[@"array"][-1]);
    AssertFalse(doc[@"array"][-1].exists);
    AssertNotNil(doc[@"array"][0]);
    Assert(doc[@"array"][0].exists);
    AssertNotNil(doc[@"array"][1]);
    AssertFalse(doc[@"array"][1].exists);
    
    AssertEqualObjects(doc[@"array"][0][@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

- (void)testArrayFragmentSetArrayObject{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject:@"Jason"];
    [array addObject:@5.5];
    [array addObject:@true];
    [doc[@"array"].array addObject:array];
    
    // pre-save check
    AssertEqualObjects(doc[@"array"][0][0].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][1].number, @5.5);
    AssertEqual(doc[@"array"][0][2].boolValue, true);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertEqualObjects(doc[@"array"][0][0].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][1].number, @5.5);
    AssertEqual(doc[@"array"][0][2].boolValue, true);
}

- (void)testArrayFragmentSetArray{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @true]];
    
    // pre-save check
    AssertEqualObjects(doc[@"array"][0][0].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][1].number, @5.5);
    AssertEqual(doc[@"array"][0][2].boolValue, true);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertEqualObjects(doc[@"array"][0][0].string, @"Jason");
    AssertEqualObjects(doc[@"array"][0][1].number, @5.5);
    AssertEqual(doc[@"array"][0][2].boolValue, true);
}

- (void)testNonExistingArrayFragmentSetObject{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @true]];
    
    doc[@"array"][0][0].value = @1;
    doc[@"array"][0][1].value = @false;
    doc[@"array"][0][2].value = @"hello";
    
    // pre-save check
    AssertEqualObjects(doc[@"array"][0][0].value, @1);
    AssertEqualObjects(doc[@"array"][0][1].value, @false);
    AssertEqualObjects(doc[@"array"][0][2].value, @"hello");
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertEqualObjects(doc[@"array"][0][0].value, @1);
    AssertEqualObjects(doc[@"array"][0][1].value, @false);
    AssertEqualObjects(doc[@"array"][0][2].value, @"hello");
}

- (void)testOutOfRangeArrayFragmentSetObject{
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @true]];
    
    doc[@"array"][0][3].value = @1;
    
    // pre-save check
    AssertNotNil(doc[@"array"][0][3]);
    AssertFalse(doc[@"array"][0][3].exists);
    
    // save
    NSError* error;
    Assert([_db saveDocument: doc error: &error], @"Saving error: %@", error);
    doc = [_db documentWithID: @"doc1"];
    
    // post save check
    AssertNotNil(doc[@"array"][0][3]);
    AssertFalse(doc[@"array"][0][3].exists);
}


- (void)testGetFragmentValues {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Star Way.",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    AssertEqualObjects(doc[@"references"][0][@"name"].string, @"Scott");
    AssertEqualObjects(doc[@"references"][1][@"name"].string, @"Sam");
    
    AssertNil(doc[@"references"][2][@"name"].value);
    AssertNil(doc[@"dummy"][@"dummy"][@"dummy"].value);
    AssertNil(doc[@"dummy"][@"dummy"][0][@"dummy"].value);
}


- (void)testSetFragmentValues {
    CBLDocument* doc = [[CBLDocument alloc] initWithID: @"doc1"];
    doc[@"name"].value = @"Jason";
    
    doc[@"address"].value = [[CBLSubdocument alloc] init];
    doc[@"address"][@"street"].value = @"1 Star Way.";
    doc[@"address"][@"phones"].value = [[CBLSubdocument alloc] init];
    doc[@"address"][@"phones"][@"mobile"].value = @"650-123-4567";
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Star Way.");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

@end
