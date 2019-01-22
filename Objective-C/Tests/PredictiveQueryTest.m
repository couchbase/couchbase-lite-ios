//
//  PredictiveQueryTest.m
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "CBLTestCase.h"
#import "CBLJSON.h"

#define PREDICTION_VALUE(MODEL, IN, PROPERTY) \
    [[CBLQueryFunction predictionUsingModel: (MODEL) input: (IN)] property: PROPERTY]

#define SEL_PREDICTION_VALUE(MODEL, IN, PROPERTY) SEL_EXPR(PREDICTION_VALUE(MODEL, IN, PROPERTY))

#define PREDICTION(MODEL, IN) \
    [CBLQueryFunction predictionUsingModel: (MODEL) input: (IN)]

#define SEL_PREDICTION(MODEL, IN) SEL_EXPR(PREDICTION(MODEL, IN))

@interface CBLTestPredictiveModel: NSObject <CBLPredictiveModel>

@property (nonatomic, readonly) NSInteger numberOfCalls;

// Override by subclasses
+ (NSString*) name;

// Override by subclasses
- (CBLDictionary*) doPredict: (CBLDictionary*)input;

// Register the model
- (void) registerModel;

// Unregister the model
- (void) unregisterModel;

// Reset number of calls
- (void) reset;

@end

@interface CBLEchoModel: CBLTestPredictiveModel
@end

@interface CBLAggregateModel: CBLTestPredictiveModel
@end

@interface CBLTextModel: CBLTestPredictiveModel
@end

@interface PredictiveQueryTest : CBLTestCase

@end

@implementation PredictiveQueryTest

- (void) setUp {
    [super setUp];
    [CBLDatabase.prediction unregisterModelWithName: [CBLAggregateModel name]];
    [CBLDatabase.prediction unregisterModelWithName: [CBLTextModel name]];
    [CBLDatabase.prediction unregisterModelWithName: [CBLEchoModel name]];
}

- (CBLMutableDocument*) createDocumentWithNumbers: (NSArray*)numbers {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    [doc setValue: numbers forKey: @"numbers"];
    [self saveDocument: doc];
    return doc;
}

- (void) testRegisterAndUnregisterModel {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PREDICTION(model, input)]
                                     from: kDATA_SRC_DB];
    
    // Query before registering the model:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in: ^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 0];
        AssertEqual([pred integerForKey: @"sum"], 15);
    }];
    AssertEqual(numRows, 1u);
    
    [aggregateModel unregisterModel];
    
    // Query after unregistering the model:
    // TODO: Should we make SQLite error domain public?:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in: ^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
}

- (void) testRegisterMultipleModelsWithSameName {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    
    NSString* model = @"TheModel";
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [CBLDatabase.prediction registerModel: aggregateModel withName: model];
    
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input))]
                                     from: kDATA_SRC_DB];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 0];
        AssertEqual([pred integerForKey: @"sum"], 15);
    }];
    AssertEqual(numRows, 1u);
    
    // Register a new model with the same name:
    CBLEchoModel* echoModel = [[CBLEchoModel alloc] init];
    [CBLDatabase.prediction registerModel: echoModel withName: model];
    
    // Query again should use the new model:
    numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 0];
        AssertNil([pred numberForKey: @"sum"]);
        AssertEqualObjects([[pred arrayForKey: @"numbers"] toArray], (@[@1, @2, @3, @4, @5]));
    }];
    AssertEqual(numRows, 1u);
    
    [CBLDatabase.prediction unregisterModelWithName: model];
}

- (void) testPredictionInputOutput {
    // Register echo model:
    CBLEchoModel* echoModel = [[CBLEchoModel alloc] init];
    [echoModel registerModel];
    
    // Create a doc:
    CBLMutableDocument *doc = [self createDocument];
    [doc setString: @"Daniel" forKey: @"name"];
    [doc setInteger: 2 forKey: @"number"];
    [self saveDocument: doc];
    
    // Create prediction function input:
    NSDate* date = [NSDate date];
    NSString* dateStr = [CBLJSON JSONObjectWithDate: date];
    NSDictionary* dict =
    @{
        // Literal:
        @"number1": @10,
        @"number2": @10.1,
        @"boolean": @YES,
        @"string": @"hello",
        @"date": date,
        @"null": [NSNull null],
        @"dict": @{@"foo": @"bar"},
        @"array": @[@"1", @"2", @"3"],
        // Expression:
        @"expr_property": EXPR_PROP(@"name"),
        @"expr_value_number1": EXPR_VAL(@20),
        @"expr_value_number2": EXPR_VAL(@20.1),
        @"expr_value_boolean": EXPR_VAL(@YES),
        @"expr_value_string": EXPR_VAL(@"hi"),
        @"expr_value_date": EXPR_VAL(date),
        @"expr_value_null": EXPR_VAL(nil),
        @"expr_value_dict": EXPR_VAL(@{@"ping": @"pong"}),
        @"expr_value_array": EXPR_VAL((@[@"4", @"5", @"6"])),
        @"expr_power": [CBLQueryFunction power: EXPR_PROP(@"number") exponent: EXPR_VAL(@2)]
    };
    
    // Execute query and validate output:
    id input = EXPR_VAL(dict);
    id model = [CBLEchoModel name];
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input))]
                                     from: kDATA_SRC_DB];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 0];
        AssertEqual(pred.count, dict.count);
        // Literal:
        AssertEqual([pred integerForKey: @"number1"], 10);
        AssertEqual([pred doubleForKey: @"number2"], 10.1);
        AssertEqual([pred booleanForKey: @"boolean"], YES);
        AssertEqualObjects([pred stringForKey: @"string"], @"hello");
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [pred dateForKey: @"date"]], dateStr);
        AssertEqualObjects([pred valueForKey: @"null"], [NSNull null]);
        AssertEqualObjects([[pred dictionaryForKey: @"dict"] toDictionary], @{@"foo": @"bar"});
        AssertEqualObjects([[pred arrayForKey: @"array"] toArray], (@[@"1", @"2", @"3"]));
        // Expression:
        AssertEqualObjects([pred stringForKey: @"expr_property"], @"Daniel");
        AssertEqual([pred integerForKey: @"expr_value_number1"], 20);
        AssertEqual([pred doubleForKey: @"expr_value_number2"], 20.1);
        AssertEqual([pred booleanForKey: @"expr_value_boolean"], YES);
        AssertEqualObjects([pred stringForKey: @"expr_value_string"], @"hi");
        AssertEqualObjects([CBLJSON JSONObjectWithDate: [pred dateForKey: @"expr_value_date"]], dateStr);
        AssertEqualObjects([pred valueForKey: @"expr_value_null"], [NSNull null]);
        AssertEqualObjects([[pred dictionaryForKey: @"expr_value_dict"] toDictionary], @{@"ping": @"pong"});
        AssertEqualObjects([[pred arrayForKey: @"expr_value_array"] toArray], (@[@"4", @"5", @"6"]));
        AssertEqual([pred integerForKey: @"expr_power"], 4);
    }];
    AssertEqual(numRows, 1u);
    
    [echoModel unregisterModel];
}

- (void) testPredictionWithBlobPropertyInput {
    NSArray* texts = @[
                       @"Knox on fox in socks in box. Socks on Knox and Knox in box.",
                       @"Clocks on fox tick. Clocks on Knox tock. Six sick bricks tick. Six sick chicks tock."
                       ];
    
    for (NSString* text in texts) {
        CBLMutableDocument* doc = [self createDocument];
        [doc setBlob: [self blobForString: text] forKey: @"text"];
        [self saveDocument: doc];
    }
    
    CBLTextModel* textModel = [[CBLTextModel alloc] init];
    [textModel registerModel];
    
    id model = [CBLTextModel name];
    id input = [CBLQueryExpression dictionary: @{ @"text": EXPR_PROP(@"text")}];
    CBLQueryExpression* prediction = PREDICTION_VALUE(model, input, @"wc");
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"text"),
                                             SEL_EXPR_AS(prediction, @"wc")]
                                     from: kDATA_SRC_DB
                                    where: [prediction greaterThan: EXPR_VAL(@15)]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        CBLBlob* blob = [r blobForKey: @"text"];
        AssertNotNil(blob);
        
        NSString* text = [[NSString alloc] initWithData: blob.content encoding: NSUTF8StringEncoding];
        AssertEqualObjects(text, texts[1]);
        AssertEqual([r integerForKey: @"wc"], 16);
    }];
    AssertEqual(numRows, 1u);
    
    [textModel unregisterModel];
}

- (void) testPredictionWithBlobParameterInput {
    Assert([self.db saveDocument: [[CBLMutableDocument alloc] init] error: nil]);
    
    CBLTextModel* textModel = [[CBLTextModel alloc] init];
    [textModel registerModel];
    
    id model = [CBLTextModel name];
    id input = [CBLQueryExpression dictionary: @{ @"text": [CBLQueryExpression parameterNamed: @"text"]}];
    CBLQueryExpression* prediction = PREDICTION_VALUE(model, input, @"wc");
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(prediction, @"wc")]
                                     from: kDATA_SRC_DB];
    
    CBLQueryParameters* params = [[CBLQueryParameters alloc] init];
    [params setBlob: [self blobForString: @"Knox on fox in socks in box. Socks on Knox and Knox in box."]
            forName: @"text"];
    q.parameters = params;
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        AssertEqual([r integerAtIndex: 0], 14);
    }];
    AssertEqual(numRows, 1u);
    
    [textModel unregisterModel];
}

- (void) testPredictionWithNonSupportedInputTypes {
    CBLEchoModel* echoModel = [[CBLEchoModel alloc] init];
    [echoModel registerModel];
    
    // Query with non dictionary input:
    id model = [CBLEchoModel name];
    id input = EXPR_VAL(@"string");
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input))]
                                     from: kDATA_SRC_DB];
    
    // TODO: Should we make SQLite error domain public?:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in: ^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
    
    // Query with non-supported value type in dictionary input:
    input = EXPR_VAL(@{ @"key": [[NSObject alloc] init] });
    [self expectException: @"NSInvalidArgumentException" in: ^{
        [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input))]
                           from: kDATA_SRC_DB];
    }];
    
    [echoModel unregisterModel];
}

- (void) testQueryPredictionResultDictionary {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR(PREDICTION(model, input))]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex: 0] toArray];
        Assert(numbers.count > 0);
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        AssertEqual([pred integerForKey: @"sum"], [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
        AssertEqual([pred integerForKey: @"min"], [[numbers valueForKeyPath:@"@min.self"] integerValue]);
        AssertEqual([pred integerForKey: @"max"], [[numbers valueForKeyPath:@"@max.self"] integerValue]);
        AssertEqual([pred integerForKey: @"avg"], [[numbers valueForKeyPath:@"@avg.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testQueryPredictionValues {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"sum"), @"sum"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"min"), @"min"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"max"), @"max"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"avg"), @"avg")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex: 0] toArray];
        Assert(numbers.count > 0);
        
        NSInteger sum = [r integerAtIndex: 1];
        NSInteger min = [r integerAtIndex: 2];
        NSInteger max = [r integerAtIndex: 3];
        NSInteger avg = [r integerAtIndex: 4];
        
        AssertEqual(sum, [r integerForKey: @"sum"]);
        AssertEqual(min, [r integerForKey: @"min"]);
        AssertEqual(max, [r integerForKey: @"max"]);
        AssertEqual(avg, [r integerForKey: @"avg"]);
        
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
        AssertEqual(min, [[numbers valueForKeyPath:@"@min.self"] integerValue]);
        AssertEqual(max, [[numbers valueForKeyPath:@"@max.self"] integerValue]);
        AssertEqual(avg, [[numbers valueForKeyPath:@"@avg.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testWhereUsingPredictionValues {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"sum"), @"sum"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"min"), @"min"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"max"), @"max"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"avg"), @"avg")]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex: 0] toArray];
        Assert(numbers.count > 0);
        
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, 15);
        
        NSInteger min = [r integerAtIndex: 2];
        NSInteger max = [r integerAtIndex: 3];
        NSInteger avg = [r integerAtIndex: 4];
        
        AssertEqual(sum, [r integerForKey: @"sum"]);
        AssertEqual(min, [r integerForKey: @"min"]);
        AssertEqual(max, [r integerForKey: @"max"]);
        AssertEqual(avg, [r integerForKey: @"avg"]);
        
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
        AssertEqual(min, [[numbers valueForKeyPath:@"@min.self"] integerValue]);
        AssertEqual(max, [[numbers valueForKeyPath:@"@max.self"] integerValue]);
        AssertEqual(avg, [[numbers valueForKeyPath:@"@avg.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    
    [aggregateModel unregisterModel];
}

- (void) testOrderByUsingPredictionValues {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(sumPrediction, @"sum")]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction greaterThan: EXPR_VAL(@1)]
                                  orderBy: @[[[CBLQuerySortOrder expression: sumPrediction] descending]]];
    
    NSMutableArray* sums = [NSMutableArray array];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        [sums addObject: [r numberAtIndex: 0]];
    }];
    AssertEqual(numRows, 2u);
    AssertEqualObjects(sums, (@[@40, @15]));
    
    [aggregateModel unregisterModel];
}

- (void) testPredictiveModelReturningNull {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    
    CBLMutableDocument* doc = [self createDocument];
    [doc setString: @"Knox on fox in socks in box. Socks on Knox and Knox in box." forKey: @"text"];
    [self saveDocument: doc];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input)),
                                             SEL_EXPR(sumPrediction)]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        if (n == 1) {
            AssertNotNil([r dictionaryAtIndex: 0]);
            AssertEqual([r integerAtIndex: 1], 15);
        } else {
            AssertNil([r valueAtIndex: 0]);
            AssertNil([r valueAtIndex: 1]);
        }
    }];
    AssertEqual(numRows, 2u);
    
    // Evaluate with nullOrMissing:
    q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(model, input)),
                                   SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"sum"), @"sum")]
                           from: kDATA_SRC_DB
                          where: [PREDICTION(model, input) notNullOrMissing]];
    
    numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        AssertNotNil([r dictionaryAtIndex: 0]);
        AssertEqual([r integerAtIndex: 1], 15);
    }];
    AssertEqual(numRows, 1u);
    
    [aggregateModel unregisterModel];
}

- (void) testIndexPredictionValueUsingValueIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    
    // Index:
    NSError* error;
    NSArray* indexItems = @[[CBLValueIndexItem expression: sumPrediction]];
    CBLValueIndex* index = [CBLIndexBuilder valueIndexWithItems: indexItems];
    Assert([self.db createIndex: index withName: @"SumIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR(sumPrediction)]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
        
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u); // The value should be cached by the index
}

- (void) testIndexMultiplePredictionValuesUsingValueIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    NSError* error;
    CBLValueIndex* sumIndex = [CBLIndexBuilder valueIndexWithItems:
                               @[[CBLValueIndexItem expression: sumPrediction]]];
    Assert([self.db createIndex: sumIndex withName: @"SumIndex" error: &error]);
    
    CBLValueIndex* avgIndex = [CBLIndexBuilder valueIndexWithItems:
                               @[[CBLValueIndexItem expression: avgPrediction]]];
    Assert([self.db createIndex: avgIndex withName: @"AvgIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(sumPrediction, @"s"),
                                             SEL_EXPR_AS(avgPrediction, @"a")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction lessThanOrEqualTo: EXPR_VAL(@15)] orExpression:
                                            [avgPrediction equalTo: EXPR_VAL(@8)]]];
    NSString* explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location != NSNotFound);
    
    int64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        Assert([r integerAtIndex: 0] == 15 || [r integerAtIndex: 1] == 8);
    }];
    AssertEqual(numRows, 2u);
}

- (void) testIndexCompoundPredictiveValuesUsingValueIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    NSError* error;
    CBLValueIndex* index = [CBLIndexBuilder valueIndexWithItems:
                            @[[CBLValueIndexItem expression: sumPrediction],
                              [CBLValueIndexItem expression: avgPrediction]]];
    Assert([self.db createIndex: index withName: @"SumAvgIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(sumPrediction, @"sum"),
                                             SEL_EXPR_AS(avgPrediction, @"avg")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction equalTo: EXPR_VAL(@15)] andExpression:
                                            [avgPrediction equalTo: EXPR_VAL(@3)]]];
    
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumAvgIndex"].location != NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        AssertEqual([r integerAtIndex: 0], 15);
        AssertEqual([r integerAtIndex: 1], 3);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 4u);
}

- (void) testIndexPredictionResultUsingPredictiveIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    
    // Index:
    NSError* error;
    CBLPredictiveIndex* index =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                     input: input
                                                                properties: nil];
    Assert([self.db createIndex: index withName: @"AggCache" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR(sumPrediction)]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    
    Assert([[q explain: nil] rangeOfString: @"USING INDEX AggCache"].location == NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
        
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u); // The value should be cached by the index
    
    [aggregateModel unregisterModel];
}

- (void) testIndexPredictionValueUsingPredictiveIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    
    // Index:
    NSError* error;
    CBLPredictiveIndex* index =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                     input: input
                                                                properties: @[@"sum"]];
    Assert([self.db createIndex: index withName: @"SumIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR(sumPrediction)]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
        
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testIndexMuliplePredictionValuesUsingPredictiveIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    NSError* error;
    CBLPredictiveIndex* sumIndex = [CBLIndexBuilder predictiveIndexWithModel: model
                                                                       input: input
                                                                  properties: @[@"sum"]];
    Assert([self.db createIndex: sumIndex withName: @"SumIndex" error: &error]);
    
    CBLPredictiveIndex* avgIndex = [CBLIndexBuilder predictiveIndexWithModel: model
                                                                       input: input
                                                                  properties: @[@"avg"]];
    Assert([self.db createIndex: avgIndex withName: @"AvgIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(sumPrediction, @"s"),
                                             SEL_EXPR_AS(avgPrediction, @"a")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction lessThanOrEqualTo: EXPR_VAL(@15)] orExpression:
                                            [avgPrediction equalTo: EXPR_VAL(@8)]]];
    NSString* explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location != NSNotFound);
    
    int64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        Assert([r integerAtIndex: 0] == 15 || [r integerAtIndex: 1] == 8);
    }];
    AssertEqual(numRows, 2u);
    AssertEqual(aggregateModel.numberOfCalls, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testIndexCompoundPredictionValuesUsingPredictiveIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    NSError* error;
    CBLPredictiveIndex* index =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                     input: input
                                                                properties: @[@"sum", @"avg"]];
    Assert([self.db createIndex: index withName: @"SumAvgIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR_AS(sumPrediction, @"sum"),
                                             SEL_EXPR_AS(avgPrediction, @"avg")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction equalTo: EXPR_VAL(@15)] andExpression:
                                            [avgPrediction equalTo: EXPR_VAL(@3)]]];
    
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumAvgIndex"].location != NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        AssertEqual([r integerAtIndex: 0], 15);
        AssertEqual([r integerAtIndex: 1], 3);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testDeletePredictiveIndex {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    
    // Index:
    NSError* error;
    CBLPredictiveIndex* index =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                     input: input
                                                                properties: @[@"sum"]];
    Assert([self.db createIndex: index withName: @"SumIndex" error: &error]);
    
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    
    // Query with index:
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u);
    
    // Delete SumIndex:
    Assert([self.db deleteIndexForName: @"SumIndex" error: &error]);
    
    // Query again:
    [aggregateModel reset];
    q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                           from: kDATA_SRC_DB
                          where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    Assert([[q explain: nil] rangeOfString: @"USING INDEX SumIndex"].location == NSNotFound);
    
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 4u); // Note: verifyQuery executes query twice
    
    [aggregateModel unregisterModel];
}

- (void) testDeletePredictiveIndexesSharingSameCacheTable {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    // Create agg index:
    NSError* error;
    CBLPredictiveIndex* aggIndex =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                          input: input
                                                                     properties: nil];
    Assert([self.db createIndex: aggIndex withName: @"AggIndex" error: &error]);
    
    // Create sum index:
    CBLPredictiveIndex* sumIndex =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                        input: input
                                                                   properties: @[@"sum"]];
    Assert([self.db createIndex: sumIndex withName: @"SumIndex" error: &error]);
    
    // Create avg index:
    CBLPredictiveIndex* avgIndex =  [CBLIndexBuilder predictiveIndexWithModel: model
                                                                        input: input
                                                                   properties: @[@"avg"]];
    Assert([self.db createIndex: avgIndex withName: @"AvgIndex" error: &error]);
    
    // Query:
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction lessThanOrEqualTo: EXPR_VAL(@15)] orExpression:
                                            [avgPrediction equalTo: EXPR_VAL(@8)]]];
    NSString* explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX SumIndex"].location != NSNotFound);
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location != NSNotFound);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 2u);
    AssertEqual(aggregateModel.numberOfCalls, 2u);
    
    // Delete SumIndex:
    Assert([self.db deleteIndexForName: @"SumIndex" error: &error]);
    
    [aggregateModel reset];
    // Note: when having only one index, SQLite optimizer doesn't utilize the index
    //       when using OR expr. Hence explicity test each index with two queries:
    q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                           from: kDATA_SRC_DB
                          where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX SumIndex"].location == NSNotFound);
    
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 0u);
    
    q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                           from: kDATA_SRC_DB
                          where: [avgPrediction equalTo: EXPR_VAL(@8)]];
    explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location != NSNotFound);
    
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 0u);
    
    // Delete AvgIndex:
    Assert([self.db deleteIndexForName: @"AvgIndex" error: &error]);
    
    [aggregateModel reset];
    q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                           from: kDATA_SRC_DB
                          where: [avgPrediction equalTo: EXPR_VAL(@8)]];
    explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location == NSNotFound);
    
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 0u); // Still using cache table
    
    // Delete AggIndex:
    Assert([self.db deleteIndexForName: @"AggIndex" error: &error]);
    
    [aggregateModel reset];
    q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers")]
                           from: kDATA_SRC_DB
                          where: [[sumPrediction lessThanOrEqualTo: EXPR_VAL(@15)] orExpression:
                                  [avgPrediction equalTo: EXPR_VAL(@8)]]];
    explain = [q explain: nil];
    Assert([explain rangeOfString: @"USING INDEX SumIndex"].location == NSNotFound);
    Assert([explain rangeOfString: @"USING INDEX AvgIndex"].location == NSNotFound);
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
    }];
    AssertEqual(numRows, 2u);
    Assert(aggregateModel.numberOfCalls > 0); // Not using cache anymore
    
    [aggregateModel unregisterModel];
}

- (void) testEuclidientDistance {
    NSArray* tests = @[@[@[@10, @10], @[@13, @14], @5],
                       @[@[@1, @2, @3], @[@1, @2, @3], @0],
                       @[@[], @[], @0],
                       @[@[@1, @2], @[@1, @2, @3], [NSNull null]],
                       @[@[@1, @2], @"foo", [NSNull null]]];
    
    for (NSArray* t in tests) {
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setValue: t[0] forKey: @"v1"];
        [doc setValue: t[1] forKey: @"v2"];
        [doc setValue: t[2] forKey: @"distance"];
        [self saveDocument: doc];
    }
    
    CBLQueryExpression* distance = [CBLQueryFunction euclideanDistanceBetween: EXPR_PROP(@"v1")
                                                                          and: EXPR_PROP(@"v2")];
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(distance), SEL_PROP(@"distance")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        AssertEqual([r valueAtIndex: 0], [r valueAtIndex: 1]);
    }];
    AssertEqual(numRows, tests.count);
}

- (void) testSquaredEuclidientDistance {
    NSArray* tests = @[@[@[@10, @10], @[@13, @14], @25.0],
                       @[@[@1, @2, @3], @[@1, @2, @3], @0.0],
                       @[@[], @[], @0.0],
                       @[@[@1, @2], @[@1, @2, @3], [NSNull null]],
                       @[@[@1, @2], @"foo", [NSNull null]]];
    
    for (NSArray* t in tests) {
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setValue: t[0] forKey: @"v1"];
        [doc setValue: t[1] forKey: @"v2"];
        [doc setValue: t[2] forKey: @"distance"];
        [self saveDocument: doc];
    }
    
    CBLQueryExpression* distance = [CBLQueryFunction squaredEuclideanDistanceBetween: EXPR_PROP(@"v1")
                                                                                 and: EXPR_PROP(@"v2")];
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(distance), SEL_PROP(@"distance")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        if (![r valueAtIndex: 1])
            AssertNil([r valueAtIndex: 0]);
        else
            AssertEqual([r doubleAtIndex: 0], [r doubleAtIndex: 1]);
    }];
    AssertEqual(numRows, tests.count);
}

- (void) testCosineDistance {
    NSArray* tests = @[@[@[@10, @0], @[@0, @99], @1.0],
                       @[@[@1, @2, @3], @[@1, @2, @3], @0.0],
                       @[@[@1, @0, @-1], @[@-1, @-1, @0], @1.5],
                       @[@[], @[], [NSNull null]],
                       @[@[@1, @2], @[@1, @2, @3], [NSNull null]],
                       @[@[@1, @2], @"foo", [NSNull null]]];
    
    for (NSArray* t in tests) {
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setValue: t[0] forKey: @"v1"];
        [doc setValue: t[1] forKey: @"v2"];
        [doc setValue: t[2] forKey: @"distance"];
        [self saveDocument: doc];
    }
    
    CBLQueryExpression* distance = [CBLQueryFunction cosineDistanceBetween: EXPR_PROP(@"v1")
                                                                       and: EXPR_PROP(@"v2")];
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(distance), SEL_PROP(@"distance")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        if (![r valueAtIndex: 1])
            AssertNil([r valueAtIndex: 0]);
        else
            AssertEqual([r doubleAtIndex: 0], [r doubleAtIndex: 1]);
    }];
    AssertEqual(numRows, tests.count);
}

@end

#pragma mark - Models

@implementation CBLTestPredictiveModel

@synthesize numberOfCalls=_numberOfCalls;

- (CBLDictionary*) predict: (CBLDictionary*)input {
    _numberOfCalls++;
    return [self doPredict: input];
}

+ (NSString*) name {
    return @"Untitled";
}

- (CBLDictionary*) doPredict: (CBLDictionary*)input {
    return nil;
}

- (void) registerModel {
    [CBLDatabase.prediction registerModel: self withName: [self.class name]];
}

- (void) unregisterModel {
    [CBLDatabase.prediction unregisterModelWithName: [self.class name]];
}

- (void) reset {
    _numberOfCalls = 0;
}

@end

@implementation CBLEchoModel

+ (NSString*) name {
    return @"EchoModel";
}

- (CBLDictionary*) doPredict: (CBLDictionary*)input {
    return input;
}

@end

@implementation CBLAggregateModel

+ (NSString*) name {
    return @"AggregateModel";
}

- (CBLDictionary*) doPredict: (CBLDictionary*)input {
    NSArray* numbers = [[input arrayForKey: @"numbers"] toArray];
    if (!numbers)
        return nil;

    CBLMutableDictionary* output = [[CBLMutableDictionary alloc] init];
    [output setValue: [numbers valueForKeyPath:@"@sum.self"] forKey: @"sum"];
    [output setValue: [numbers valueForKeyPath:@"@min.self"] forKey: @"min"];
    [output setValue: [numbers valueForKeyPath:@"@max.self"] forKey: @"max"];
    [output setValue: [numbers valueForKeyPath:@"@avg.self"] forKey: @"avg"];
    return output;
}

@end

@implementation CBLTextModel

+ (NSString*) name {
    return @"TextModel";
}

- (CBLDictionary*) doPredict: (CBLDictionary*)input {
    CBLBlob* blob = [input blobForKey: @"text"];
    if (!blob)
        return nil;
    
    if (![blob.contentType isEqualToString: @"text/plain"]) {
        NSLog(@"WARN: Invalid blob content type; not text/plain.");
        return nil;
    }
    
    NSString* text = [[NSString alloc] initWithData: blob.content
                                           encoding: NSUTF8StringEncoding];
    
    __block NSUInteger wc = 0;
    __block NSUInteger sc = 0;
    __block NSUInteger curSentLoc = NSNotFound;
    [text enumerateLinguisticTagsInRange: NSMakeRange(0, [text length])
                                  scheme: NSLinguisticTagSchemeTokenType
                                 options: 0
                             orthography: nil
                              usingBlock: ^(NSLinguisticTag tag, NSRange token, NSRange sent, BOOL* stop)
    {
        if (tag == NSLinguisticTagWord)
            wc++;
        if (sent.location != NSNotFound && sent.location != curSentLoc) {
            curSentLoc = sent.location;
            sc++;
        }
    }];
    
    CBLMutableDictionary* output = [[CBLMutableDictionary alloc] init];
    [output setInteger: wc forKey: @"wc"];
    [output setInteger: sc forKey: @"sc"];
    return output;
}

@end
