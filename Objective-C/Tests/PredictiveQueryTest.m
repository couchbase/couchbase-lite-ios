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
- (CBLDictionary*) predict: (CBLDictionary*)input;

// Register the model
- (void) registerModel;

// Unregister the model
- (void) unregisterModel;

// Reset number of calls
- (void) reset;

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
}

- (CBLMutableDocument*) createDocumentWithNumbers: (NSArray*)numbers {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    [doc setValue: numbers forKey: @"numbers"];
    [self saveDocument: doc];
    return doc;
}

- (void) testRegisterAndUnregisterModel {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_PREDICTION(model, input)]
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
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        Assert(numbers.count > 0);
        
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        AssertNotNil(pred);
        AssertEqual([pred integerForKey: @"sum"], [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
        AssertEqual([pred integerForKey: @"min"], [[numbers valueForKeyPath:@"@min.self"] integerValue]);
        AssertEqual([pred integerForKey: @"max"], [[numbers valueForKeyPath:@"@max.self"] integerValue]);
        AssertEqual([pred integerForKey: @"avg"], [[numbers valueForKeyPath:@"@avg.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [aggregateModel unregisterModel];
    
    // Query after unregistering the model:
    // TODO: Should we make SQLite error domain public:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in: ^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
}

- (void) testQueryDictionaryResult {
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

- (void) testQueryValueFromDictionaryResult {
    [self createDocumentWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocumentWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [aggregateModel registerModel];
    
    id model = [CBLAggregateModel name];
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"sum"), @"sum")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex: 0] toArray];
        Assert(numbers.count > 0);
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [r integerForKey: @"sum"]);
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [aggregateModel unregisterModel];
}

- (void) testQueryWithBlobProperty {
    NSArray* texts = @[
        @"Knox on fox in socks in box. Socks on Knox and Knox in box.",
        @"Clocks on fox tick. Clocks on Knox tock. Six sick bricks tick. Six sick chicks tock."
    ];
    
    for (NSString* text in texts) {
        CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
        [doc setBlob: [self blobForString: text] forKey: @"text"];
        Assert([self.db saveDocument: doc error: nil]);
    }
    
    CBLTextModel* textModel = [[CBLTextModel alloc] init];
    [textModel registerModel];
    
    id model = [CBLTextModel name];
    id input = [CBLQueryExpression dictionary: @{ @"text": @[@"BLOB", @".text"]}];
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

- (void) testQueryWithBlobParameter {
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

- (void) testIndexPredictionValue {
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

- (void) testIndexMultiplePredictionValues {
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

- (void) testIndexCompoundPredictiveValues {
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

- (CBLDictionary*) prediction: (CBLDictionary *)input {
    _numberOfCalls++;
    return [self predict: input];
}

+ (NSString*) name {
    return @"Untitled";
}

- (CBLDictionary*) predict: (CBLDictionary*)input {
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

@implementation CBLAggregateModel

+ (NSString*) name {
    return @"AggregateModel";
}

- (CBLDictionary*) predict: (CBLDictionary*)input {
    NSArray* numbers = [[input arrayForKey: @"numbers"] toArray];
    if (!numbers) {
        NSLog(@"WARNING: numbers is nil");
        return nil;
    }

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

- (CBLDictionary*) predict: (CBLDictionary*)input {
    CBLBlob* blob = [input blobForKey: @"text"];
    if (!blob) {
        NSLog(@"WARNING: text is nil");
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

