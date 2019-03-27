//
//  FragmentTest.m
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

@interface FragmentTest : CBLTestCase
@end


@implementation FragmentTest


- (void) testBasicGetFragmentValues {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setData: @{ @"name": @"Jason",
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


- (void) testBasicSetFragmentValues {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"name"].value = @"Jason";
    
    doc[@"address"].value = [[CBLMutableDictionary alloc] init];
    doc[@"address"][@"street"].value = @"1 Main Street";
    doc[@"address"][@"phones"].value = [[CBLMutableDictionary alloc] init];
    doc[@"address"][@"phones"][@"mobile"].value = @"650-123-4567";
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqualObjects(doc[@"address"][@"street"].string, @"1 Main Street");
    AssertEqualObjects(doc[@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
}

- (void) testFragmentTypeSetterMethodsWithKey {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"name"].string = @"Jason";
    doc[@"id"].longLongValue = 123456789;
    doc[@"age"].number = @(21);
    doc[@"totalScore"].integerValue = 100;
    doc[@"earnedScore"].floatValue = 67.89f;
    doc[@"gpa"].doubleValue = 3.469;
    doc[@"hasHobby"].booleanValue = YES;
    NSDate* twoWeeksBack = [NSDate dateWithTimeIntervalSinceNow: 2 * 24 * 60 * 60];
    doc[@"startDate"].date = twoWeeksBack;
    
    NSData* content = [@"I am cool" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    doc[@"about"].blob = blob;
    
    CBLMutableArray* phones = [[CBLMutableArray alloc] initWithData: @[@"920-456-7890",
                                                                       @"920-123-4566"]];
    doc[@"phone"].array = phones;
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] initWithData: @{@"1": @"submitted",
                                                                               @"2": @"pending",
                                                                               @"3": @"pending",
                                                                               }];
    doc[@"assignments"].dictionary = dict;
    
    AssertEqualObjects(doc[@"name"].string, @"Jason");
    AssertEqual(doc[@"id"].longLongValue, 123456789);
    AssertEqualObjects(doc[@"age"].number, @21);
    AssertEqual(doc[@"totalScore"].integerValue, 100);
    AssertEqual(doc[@"earnedScore"].floatValue, 67.89f);
    AssertEqual(doc[@"gpa"].doubleValue, 3.469);
    AssertEqual(doc[@"hasHobby"].booleanValue, YES);
    Assert([doc[@"startDate"].date timeIntervalSinceDate: twoWeeksBack] < 1);
    AssertEqualObjects(doc[@"about"].blob, blob);
    AssertEqualObjects(doc[@"phone"].array, phones);
    AssertEqualObjects(doc[@"assignments"].dictionary, dict);
}

- (void) testFragmentTypeSetterMethodsWithIndex {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    NSString* key = @"info";
    NSMutableArray* array = [NSMutableArray array];
    for (uint i =0; i < 12; i++) {
        [array addObject: [NSNull null]];
    }
    
    [doc setValue: [[CBLMutableArray alloc] initWithData: array] forKey: key];
    doc[key][0].string = @"Jason";
    doc[key][1].longLongValue = 123456789;
    doc[key][2].number = @(21);
    doc[key][3].integerValue = 100;
    doc[key][4].floatValue = 67.89f;
    doc[key][5].doubleValue = 3.469;
    doc[key][6].booleanValue = YES;
    NSDate* twoWeeksBack = [NSDate dateWithTimeIntervalSinceNow: 2 * 24 * 60 * 60];
    doc[key][7].date = twoWeeksBack;

    NSData* content = [@"I am cool" dataUsingEncoding: NSUTF8StringEncoding];
    CBLBlob* blob = [[CBLBlob alloc] initWithContentType:@"text/plain" data: content];
    doc[key][8].blob = blob;

    CBLMutableArray* phones = [[CBLMutableArray alloc] initWithData: @[@"920-456-7890",
                                                                       @"920-123-4566"]];
    doc[key][9].array = phones;
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] initWithData: @{@"1": @"submitted",
                                                                               @"2": @"pending",
                                                                               @"3": @"pending",
                                                                               }];
    doc[key][10].dictionary = dict;
    doc[key][11].value = @"updatedValue";
    
    AssertEqualObjects(doc[key][0].string, @"Jason");
    AssertEqual(doc[key][1].longLongValue, 123456789);
    AssertEqualObjects(doc[key][2].number, @21);
    AssertEqual(doc[key][3].integerValue, 100);
    AssertEqual(doc[key][4].floatValue, 67.89f);
    AssertEqual(doc[key][5].doubleValue, 3.469);
    AssertEqual(doc[key][6].booleanValue, YES);
    Assert([doc[key][7].date timeIntervalSinceDate: twoWeeksBack] < 1);
    AssertEqualObjects(doc[key][8].blob, blob);
    AssertEqualObjects(doc[key][9].array, phones);
    AssertEqualObjects(doc[key][10].dictionary, dict);
    AssertEqualObjects(doc[key][11].value, @"updatedValue");
}

- (void) testGetDocFragmentWithID {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main street",
                                   @"city": @"Mountain View",
                                   @"state": @"CA"}};
    [self saveDocument: [self createDocument: @"doc1" data: dict]];
    
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
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
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
        AssertEqual(fragment.booleanValue, YES);
        AssertNil(fragment.array);
        AssertNotNil(fragment.value);
        AssertNotNil(fragment.dictionary);
        AssertEqual(fragment.dictionary, fragment.value);
        AssertEqualObjects([fragment.dictionary toDictionary], dict[@"address"]);
    }];
}


- (void) testGetFragmentFromArrayValue {
    NSDictionary* dict = @{@"references": @[@{@"name": @"Scott"}, @{@"name": @"Sam"}]};
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
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
        AssertEqual(fragment.booleanValue, YES);
        AssertNil(fragment.dictionary);
        AssertNotNil(fragment.value);
        AssertNotNil(fragment.array);
        AssertEqual(fragment.array, fragment.value);
        AssertEqualObjects([fragment.array toArray], dict[@"references"]);
    }];
}


- (void) testGetFragmentFromInteger {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(10) forKey: @"integer"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"integer"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @10);
        AssertEqual(fragment.integerValue, 10);
        AssertEqual(fragment.floatValue, 10.0f);
        AssertEqual(fragment.doubleValue, 10.0);
        AssertEqual(fragment.booleanValue, YES);
    }];
}


- (void) testGetFragmentFromFloat {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(100.10) forKey: @"float"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"float"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @100.10);
        AssertEqual(fragment.integerValue, 100);
        AssertEqual(fragment.floatValue, 100.10f);
        AssertEqual(fragment.doubleValue, 100.10);
        AssertEqual(fragment.booleanValue, YES);
    }];
}


- (void) testGetFragmentFromDouble {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @(99.99) forKey: @"double"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"double"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @(99.99));
        AssertEqual(fragment.integerValue, 99);
        AssertEqual(fragment.floatValue, 99.99f);
        AssertEqual(fragment.doubleValue, 99.99);
        AssertEqual(fragment.booleanValue, YES);
    }];
}


- (void) testGetFragmentFromBoolean {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @YES forKey: @"boolean"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"boolean"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.dictionary);
        AssertNil(fragment.array);
        AssertNotNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.number, fragment.value);
        AssertEqualObjects(fragment.number, @1);
        AssertEqual(fragment.integerValue, 1);
        AssertEqual(fragment.floatValue, 1.0f);
        AssertEqual(fragment.doubleValue, 1.0);
        AssertEqual(fragment.booleanValue, YES);
    }];
}


// get all types of fragments from date
- (void) testGetFragmentFromDate {
    NSDate* date = [NSDate date];
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: date forKey: @"date"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"date"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNotNil(fragment.string);
        AssertNotNil(fragment.date);
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date], fragment.value);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: fragment.date],
                           [CBLJSON JSONObjectWithDate: date]);
        XCTAssertEqualWithAccuracy([fragment.date timeIntervalSinceReferenceDate],
                                   [date timeIntervalSinceReferenceDate], 0.001);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f); 
        AssertEqual(fragment.doubleValue, 0.0);; 
        AssertEqual(fragment.booleanValue, YES);
    }];
}


- (void) testGetFragmentFromString {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"hello world" forKey: @"string"];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"string"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNotNil(fragment.string);
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertNil(fragment.array); 
        AssertNil(fragment.number);
        AssertNotNil(fragment.value);
        AssertEqualObjects(fragment.string, fragment.value);
        AssertEqualObjects(fragment.string, @"hello world");
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.booleanValue, YES);
    }];
}


- (void) testGetNestedDictionaryFragment {
    NSDictionary* dict = @{@"address": @{
                                   @"street": @"1 Main Street",
                                   @"phones": @{@"mobile": @"650-123-4567"}
                                   }};
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"address"][@"phones"];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string);
        AssertNil(fragment.date);
        AssertNil(fragment.array);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.booleanValue, YES);
        AssertNotNil(fragment.dictionary);
        AssertNotNil(fragment.value);
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
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"address"][@"country"];
        AssertNotNil(fragment);
        AssertFalse(fragment.exists);
        AssertNil(fragment.string);       
        AssertNil(fragment.date);       
        AssertNil(fragment.array);       
        AssertNil(fragment.dictionary);
        AssertNil(fragment.value);          
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);; 
        AssertEqual(fragment.booleanValue, NO);
    }];
}


- (void)testGetNestedArrayFragments {
    NSDictionary* dict = @{@"nested-array": @[@[@1, @2, @3], @[@4, @5, @6]]};
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"nested-array"][1];
        AssertNotNil(fragment);
        Assert(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary); 
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertEqual(fragment.booleanValue, YES);
        AssertNotNil(fragment.value); 
        AssertNotNil(fragment.array);
        AssertEqual(fragment.array, fragment.value);
        AssertEqualObjects([fragment.array toArray], dict[@"nested-array"][1]);
        AssertEqual(3, (int)[fragment.array toArray].count);
    }];
}


- (void) testGetNestedNonExistingArrayFragments {
    NSDictionary* dict = @{@"nested-array": @[@[@1, @2, @3], @[@4, @5, @6]]};
    CBLMutableDocument* doc = [self createDocument: @"doc1" data: dict];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLFragment* fragment = d[@"nested-array"][2];
        AssertFalse(fragment.exists);
        AssertNil(fragment.string); 
        AssertNil(fragment.date); 
        AssertNil(fragment.dictionary);
        AssertNil(fragment.value);    
        AssertNil(fragment.array);
        AssertEqual(fragment.integerValue, 0);
        AssertEqual(fragment.floatValue, 0.0f);
        AssertEqual(fragment.doubleValue, 0.0);;
        AssertFalse(fragment.booleanValue);
    }];
}


- (void) testDictionaryFragmentSet {
    NSDate* date = [NSDate date];
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"string"].value = @"value";
    doc[@"bool"].value = @YES;
    doc[@"int"].value = @7;
    doc[@"float"].value = @2.2f;
    doc[@"double"].value = @3.3;
    doc[@"date"].value = date;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"string"].string, @"value");
        AssertEqual(d[@"bool"].booleanValue, YES);
        AssertEqual(d[@"int"].integerValue, 7);
        AssertEqual(d[@"float"].floatValue, 2.2f);
        AssertEqual(d[@"double"].doubleValue, 3.3);
        AssertEqualObjects([CBLJSON JSONObjectWithDate: d[@"date"].date],
                           [CBLJSON JSONObjectWithDate: date]);
    }];
}


- (void) testDictionaryFragmentSetDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableDictionary *dict = [[CBLMutableDictionary alloc] init];
    [dict setValue: @"Jason" forKey:@"name"];
    [dict setValue: @{@"street": @"1 Main Street",
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
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    CBLMutableArray *array = [[CBLMutableArray alloc] init];
    [array setData: @[@0, @1, @2]];
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
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
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
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
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


- (void) testNonDictionaryFragmentSetValue {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    [doc setValue: @"value1" forKey: @"string1"];
    [doc setValue: @"value2" forKey: @"string2"];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        CBLMutableDocument* md = [d toMutable];
        md[@"string1"].value = @10;
        AssertEqualObjects(md[@"string1"].value, @10);
        AssertEqualObjects(md[@"string2"].value, @"value2");
    }];
}


- (void) testArrayFragmentSet {
    NSDate* date = [NSDate date];
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    Assert([[doc valueForKey: @"array"] isKindOfClass: [CBLMutableArray class]]);
    [doc[@"array"].array addValue: @"string"];
    [doc[@"array"].array addValue: @10];
    [doc[@"array"].array addValue: @10.10];
    [doc[@"array"].array addValue: @YES];
    [doc[@"array"].array addValue: date];
    Assert([[doc valueForKey: @"array"] isKindOfClass: [CBLMutableArray class]]);

    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertFalse(d[@"array"][-1].exists);
        for(int i = 0; i < 5; i++){
            AssertNotNil(d[@"array"][i]);
            Assert(d[@"array"][i].exists);
        }
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
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    CBLMutableDictionary *dict = [[CBLMutableDictionary alloc] init];
    [dict setValue: @"Jason" forKey: @"name"];
    [dict setValue: @{@"street": @"1 Main Street",@"phones": @{@"mobile": @"650-123-4567"}}
            forKey: @"address"];
    [doc[@"array"].array addValue: dict];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertFalse(d[@"array"][-1].exists);
        AssertNotNil(d[@"array"][0]);
        Assert(d[@"array"][0].exists);
        AssertFalse(d[@"array"][1].exists);
        
        AssertEqualObjects(d[@"array"][0][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testArrayFragmentSetNSDictionary {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addValue: @{@"name":@"Jason",
                                     @"address": @{@"street": @"1 Main Street",
                                                   @"phones": @{@"mobile": @"650-123-4567"}}}];
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertFalse(d[@"array"][-1].exists);
        AssertNotNil(d[@"array"][0]);
        Assert(d[@"array"][0].exists);
        AssertFalse(d[@"array"][1].exists);
        
        AssertEqualObjects(d[@"array"][0][@"name"].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][@"address"][@"street"].string, @"1 Main Street");
        AssertEqualObjects(d[@"array"][0][@"address"][@"phones"][@"mobile"].string, @"650-123-4567");
    }];
}


- (void) testArrayFragmentSetArrayObject {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    CBLMutableArray* array = [[CBLMutableArray alloc] init];
    [array addValue: @"Jason"];
    [array addValue: @5.5];
    [array addValue: @YES];
    [doc[@"array"].array addValue:array];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"array"][0][0].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][1].number, @5.5);
        AssertEqual(d[@"array"][0][2].booleanValue, YES);
    }];
}


- (void) testArrayFragmentSetArray {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addValue:@[@"Jason", @5.5, @YES]];
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertEqualObjects(d[@"array"][0][0].string, @"Jason");
        AssertEqualObjects(d[@"array"][0][1].number, @5.5);
        AssertEqual(d[@"array"][0][2].booleanValue, YES);
    }];
}


- (void) testNonExistingArrayFragmentSetObject {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"][0][0].value = @1;
    doc[@"array"][0][1].value = @NO;
    doc[@"array"][0][2].value = @"hello";
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertNil(d[@"array"][0][0].value);
        AssertNil(d[@"array"][0][1].value);
        AssertNil(d[@"array"][0][2].value);
        AssertEqualObjects(d.toDictionary, @{});
    }];
}


- (void) testOutOfRangeArrayFragmentSetObject {
    CBLMutableDocument* doc = [self createDocument: @"doc1"];
    doc[@"array"].value = @[];
    [doc[@"array"].array addValue:@[@"Jason", @5.5, @YES]];
    doc[@"array"][0][3].value = @1;
    
    [self saveDocument: doc eval: ^(CBLDocument* d) {
        AssertFalse(d[@"array"][0][3].exists);
    }];
}


@end
