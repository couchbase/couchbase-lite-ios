//
//  FragmentTest.m
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/21/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

@interface FragmentTest : CBLTestCase
@end


@implementation FragmentTest


- (void) testGetDocFragmentWithID {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}};
    [self saveDocument: [self createDocument: @"doc1" dictionary: dict]];
    
    CBLDocumentFragment* doc = _db[@"doc1"];
    AssertNotNil(doc);
    Assert(doc.exists);
    AssertNotNil(doc.document);
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Main street");
    AssertEqualObjects(doc[@"address"][@"city"].string, @"Mountain View");
    AssertEqualObjects(doc[@"address"][@"state"].string, @"CA");
    
}


- (void) testGetDocFragmentWithNonExistingID {
    CBLDocumentFragment* doc = _db[@"doc1"];
    AssertNotNil(doc);
    AssertFalse(doc.exists);
    AssertNil(doc.document);
    AssertNil(doc[@"address"][@"street"].string);
    AssertNil(doc[@"address"][@"city"].string);
    AssertNil(doc[@"address"][@"state"].string);
}


- (void) testGetFragmentFromDictionaryValue {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"address"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.number);
        AssertNil(fragment.date);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);
        AssertEqual(fragment.boolValue, YES);
        AssertNil(fragment.array);
        AssertNotNil(fragment.object);
        AssertNotNil(fragment.value);
        AssertNotNil(fragment.dictionary);
        AssertEqual(fragment.dictionary, fragment.object);
        AssertEqual(fragment.dictionary, fragment.value);
        AssertEqualObjects([fragment.dictionary toDictionary], dict[@"address"]);
    }];
}


- (void) testGetFragmentFromArrayValue {
    NSDictionary* dict = @{@"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"references"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.number);
        AssertNil(fragment.date);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);
        AssertEqual(fragment.boolValue, YES);
        AssertNil(fragment.dictionary);
        AssertNotNil(fragment.object);
        AssertNotNil(fragment.value);
        AssertNotNil(fragment.array);
        AssertEqual(fragment.array, fragment.object);
        AssertEqual(fragment.array, fragment.value);
        AssertEqualObjects([fragment.array toArray], dict[@"references"]);
    }];
}


// get all types of fragments from integer
- (void) testGetFragmentFromInteger {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @10 forKey: @"integer"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"integer"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.object);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.object);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @10);
        AssertEqual(fragment.integerValue, 10);
        AssertEqual(fragment.floatValue, 10.0f);
        AssertEqual(fragment.doubleValue, 10.0);
        AssertEqual(fragment.boolValue, YES);
    }];
}


- (void) testGetFragmentFromFloat {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @100.10 forKey: @"float"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"float"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.object);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.object);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @100.10);
        AssertEqual(fragment.integerValue, 100);
        AssertEqual(fragment.floatValue, 100.10f);
        AssertEqual(fragment.doubleValue, 100.10);
        AssertEqual(fragment.boolValue, YES);
    }];
}


- (void) testGetFragmentFromDouble {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @(99.99) forKey: @"double"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"double"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNotNil(fragment.number); 
        AssertNotNil(fragment.object); 
        AssertNotNil(fragment.value); 
        AssertEqualObjects(fragment.number, fragment.object);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @(99.99));
        AssertEqual(fragment.integerValue, 99);
        AssertEqual(fragment.floatValue, 99.99f);
        AssertEqual(fragment.doubleValue, 99.99);
        AssertEqual(fragment.boolValue, YES);
    }];
}


- (void) testGetFragmentFromBoolean {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @YES forKey: @"boolean"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"boolean"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.object);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.object);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @1);
        AssertEqual(fragment.integerValue, 1);
        AssertEqual(fragment.floatValue, 1.0f);
        AssertEqual(fragment.doubleValue, 1.0);
        AssertEqual(fragment.boolValue, YES);
    }];
}


// get all types of fragments from date
- (void) testGetFragmentFromDate {
    NSDate* date = [NSDate date];
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: date forKey: @"date"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"date"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNotNil(fragment.string);
        AssertNotNil(fragment.date);
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNil(fragment.number);    
        AssertNotNil(fragment.object); 
        AssertNotNil(fragment.value); 
        AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.object);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.value);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date],
                           [CBLJSON JSONObjectWithDate: date]);
        XCTAssertEqualWithAccuracy([fragment.date timeIntervalSinceReferenceDate],
                                   [date timeIntervalSinceReferenceDate], 0.001);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f); 
        AssertEqual(fragment.doubleValue, 0.0);; 
        AssertEqual(fragment.boolValue, YES); 
    }];
}


- (void) testGetFragmentFromString {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"hello world" forKey: @"string"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"string"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNotNil(fragment.string);
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNil(fragment.number);    
        AssertNotNil(fragment.object); 
        AssertNotNil(fragment.value); 
        AssertEqualObjects(fragment.string, fragment.object);
        AssertEqualObjects(fragment.string, fragment.value);
        AssertEqualObjects(fragment.string, @"hello world");
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.boolValue, YES);
    }];
}


- (void) testGetNestedDictionaryFragment {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main Street",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"address"][@"phones"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.array);
        AssertEqual(0, fragment.integerValue);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.boolValue, YES);
        AssertNotNil(fragment.dictionary); 
        AssertNotNil(fragment.object);    
        AssertNotNil(fragment.value);    
        AssertEqual(fragment.dictionary, fragment.object);
        AssertEqual(fragment.dictionary, fragment.value);
        AssertEqualObjects([fragment.dictionary toDictionary], dict[@"address"][@"phones"]);
        AssertEqual(1, (int)[[fragment.dictionary toDictionary] count]);
    }];
}


- (void) testGetNestedNonExistingDictionaryFragment {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main Street",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"address"][@"country"];
        AssertNotNil(fragment);
        AssertFalse(fragment.exists);
        AssertNil(fragment.string);       
        AssertNil(fragment.date);       
        AssertNil(fragment.array);       
        AssertNil(fragment.dictionary);       
        AssertNil(fragment.object);          
        AssertNil(fragment.value);          
        AssertEqual(0, fragment.integerValue);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);; 
        AssertEqual(false, fragment.boolValue);
    }];
}


- (void)testGetNestedArrayFragments {
    NSDictionary* dict = @{@"nested-array": @[@[@1, @2, @3], @[@4, @5, @6]]};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"nested-array"][1];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertEqual(0, fragment.integerValue);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.boolValue, YES);
        AssertNotNil(fragment.object); 
        AssertNotNil(fragment.value); 
        AssertNotNil(fragment.array);
        AssertEqual(fragment.array, fragment.object);
        AssertEqual(fragment.array, fragment.value);
        AssertEqualObjects([fragment.array toArray], dict[@"nested-array"][1]);
        AssertEqual(3, (int)[fragment.array toArray].count);
    }];
}


- (void) testGetNestedNonExistingArrayFragments {
    NSDictionary* dict = @{@"nested-array": @[@[@1, @2, @3], @[@4, @5, @6]]};
    CBLDocument* doc = [self createDocument: @"doc1" dictionary: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"nested-array"][2];
        AssertNotNil(fragment);
        AssertFalse(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary);
        AssertNil(fragment.object);    
        AssertNil(fragment.value);    
        AssertNil(fragment.array);
        AssertEqual(0, fragment.integerValue);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertFalse(fragment.boolValue);
    }];
}


- (void) testDictionaryFragmentSet {
    NSDate* date = [NSDate date];
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"string"].value = @"value";
    doc[@"bool"].value = @YES;
    doc[@"int"].value = @7;
    doc[@"float"].value = @2.2f;
    doc[@"double"].value = @3.3;
    doc[@"date"].value = date;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(@"value", d[@"string"].string);
        AssertEqual(YES, d[@"bool"].boolValue);
        AssertEqual(d[@"int"].integerValue, 7);
        AssertEqual(d[@"float"].floatValue, 2.2f);
        AssertEqual(d[@"double"].doubleValue, 3.3);
        XCTAssertEqualWithAccuracy([d[@"date"].date timeIntervalSinceReferenceDate],
                                   [date timeIntervalSinceReferenceDate], 0.001);
    }];
}


- (void) testDictionaryFragmentSetDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLDictionary *dict = [[CBLDictionary alloc] init];
    [dict setObject: @"Jason" forKey:@"name"];
    [dict setObject: @{@"street": @"1 Main Street",
                         @"phones": @{@"mobile": @"650-123-4567"}}
               forKey: @"address"];
    doc[@"dict"].value = dict;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"dict"][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"dict"][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"dict"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testDictionaryFragmentSetArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
    CBLArray *array = [[CBLArray alloc] init];
    [array setArray: @[@0, @1, @2]];
    doc[@"array"].value = array;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil(d[@"array"][-1].number);
        AssertFalse(d[@"array"][-1].exists);
        AssertEqualObjects(d[@"array"][0].number, @0);
        AssertEqualObjects(d[@"array"][1].number, @1);
        AssertEqualObjects(d[@"array"][2].number, @2);
        AssertNil(d[@"array"][3].number);
        AssertFalse(d[@"array"][3].exists);
    }];
}


- (void) testDictionaryFragmentSetNSDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"dict"].value = @{ @"name": @"Jason",
                            @"address": @{
                                    @"street": @"1 Main Street",
                                    @"phones": @{@"mobile": @"650-123-4567"}}};
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"dict"][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"dict"][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"dict"][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testDictionaryFragmentSetNSArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"dict"].value = @{};
    doc[@"dict"][@"array"].value = @[@0, @1, @2];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil(d[@"dict"][@"array"][-1].number);
        AssertFalse(d[@"dict"][@"array"][-1].exists);
        AssertEqualObjects(d[@"dict"][@"array"][0].number, @0);
        AssertEqualObjects(d[@"dict"][@"array"][1].number, @1);
        AssertEqualObjects(d[@"dict"][@"array"][2].number, @2);
        AssertNil(d[@"dict"][@"array"][3].number);
        AssertFalse(d[@"dict"][@"array"][3].exists);
    }];
}


- (void) testNonDictionaryFragmentSetObject {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setObject: @"value1" forKey: @"string1"];
    [doc setObject: @"value2" forKey: @"string2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        d[@"string1"].value = @10;
        AssertEqualObjects(d[@"string1"].value, @10);
        AssertEqualObjects(@"value2", d[@"string2"].value);
    }];
}


- (void) testArrayFragmentSet {
    NSDate* date = [NSDate date];
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject: @"string"];
    [doc[@"array"].array addObject: @10];
    [doc[@"array"].array addObject: @10.10];
    [doc[@"array"].array addObject: @YES];
    [doc[@"array"].array addObject: date];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNotNil(d[@"array"][-1]);
        AssertFalse(d[@"array"][-1].exists);
        for(int i = 0; i < 5; i++){
            AssertNotNil(d[@"array"][i]);
            Assert(d[@"array"][i].exists);
        }
        AssertNotNil(d[@"array"][5]);
        AssertFalse(d[@"array"][5].exists);
        
        AssertEqualObjects(@"string", d[@"array"][0].value);
        AssertEqualObjects(d[@"array"][1].value, @10);
        AssertEqualObjects(d[@"array"][2].value, @10.10);
        AssertEqualObjects(d[@"array"][3].value, @YES);
        XCTAssertEqualWithAccuracy([d[@"array"][4].date timeIntervalSinceReferenceDate],
                                   [date timeIntervalSinceReferenceDate], 0.001);
    }];
}


- (void) testArrayFragmentSetDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    CBLDictionary *dict = [[CBLDictionary alloc] init];
    [dict setObject: @"Jason" forKey: @"name"];
    [dict setObject: @{@"street": @"1 Main Street",@"phones": @{@"mobile": @"650-123-4567"}}
               forKey: @"address"];
    [doc[@"array"].array addObject: dict];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNotNil(d[@"array"][-1]);
        AssertFalse(d[@"array"][-1].exists);
        AssertNotNil(d[@"array"][0]);
        Assert(d[@"array"][0].exists);
        AssertNotNil(d[@"array"][1]);
        AssertFalse(d[@"array"][1].exists);
        
        AssertEqualObjects(d[@"array"][0][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testArrayFragmentSetNSDictionary {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject: @{@"name":@"Jason",
                                      @"address": @{@"street": @"1 Main Street",
                                                   @"phones": @{@"mobile": @"650-123-4567"}}}];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNotNil(d[@"array"][-1]);
        AssertFalse(d[@"array"][-1].exists);
        AssertNotNil(d[@"array"][0]);
        Assert(d[@"array"][0].exists);
        AssertNotNil(d[@"array"][1]);
        AssertFalse(d[@"array"][1].exists);
        
        AssertEqualObjects(d[@"array"][0][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testArrayFragmentSetArrayObject {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    CBLArray* array = [[CBLArray alloc] init];
    [array addObject: @"Jason"];
    [array addObject: @5.5];
    [array addObject: @YES];
    [doc[@"array"].array addObject:array];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"array"][0][0].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][1].number, @5.5);
        AssertEqual(d[@"array"][0][2].boolValue, YES);
    }];
}


- (void) testArrayFragmentSetArray {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @YES]];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"array"][0][0].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][1].number, @5.5);
        AssertEqual(d[@"array"][0][2].boolValue, YES);
    }];
}


- (void) testNonExistingArrayFragmentSetObject {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @YES]];
    
    doc[@"array"][0][0].value = @1;
    doc[@"array"][0][1].value = @NO;
    doc[@"array"][0][2].value = @"hello";
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"array"][0][0].value, @1);
        AssertEqualObjects(d[@"array"][0][1].value, @NO);
        AssertEqualObjects(d[@"array"][0][2].value, @"hello");
    }];
}


- (void) testOutOfRangeArrayFragmentSetObject {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addObject:@[@"Jason", @5.5, @YES]];
    doc[@"array"][0][3].value = @1;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNotNil(d[@"array"][0][3]);
        AssertFalse(d[@"array"][0][3].exists);
    }];
}


- (void) testGetFragmentValues {
    CBLDocument* doc = [self createDocument: @"doc1"];
    [doc setDictionary: @{ @"name": @"Jason",
                           @"address": @{
                                   @"street": @"1 Main Street",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   },
                           @"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]
                           }];
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Main Street");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    AssertEqualObjects(doc[@"references"][0][@"name"].string, @"Scott");
    AssertEqualObjects(doc[@"references"][1][@"name"].string, @"Sam");
    
    AssertNil(doc[@"references"][2][@"name"].value);
    AssertNil(doc[@"dummy"][@"dummy"][@"dummy"].value);
    AssertNil(doc[@"dummy"][@"dummy"][0][@"dummy"].value);
}


- (void) testSetFragmentValues {
    CBLDocument* doc = [self createDocument: @"doc1"];
    doc[@"name"].value = @"Jason";
    
    doc[@"address"].value = [[CBLDictionary alloc] init];
    doc[@"address"][@"street"].value = @"1 Main Street";
    doc[@"address"][@"phones"].value = [[CBLDictionary alloc] init];
    doc[@"address"][@"phones"][@"mobile"].value = @"650-123-4567";
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Main Street");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

@end
