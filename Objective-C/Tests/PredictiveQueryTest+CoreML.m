//
//  PredictiveQueryTest+CoreML.m
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
#import "CBLCoreMLPredictiveModel+Internal.h"

API_AVAILABLE(macos(10.13), ios(11.0))
@interface PredictiveQueryWithCoreMLTest : CBLTestCase

@end


@implementation PredictiveQueryWithCoreMLTest


- (MLModel*) coreMLModel: (NSString*)name mustExist: (BOOL)mustExist {
    NSString* resource = [NSString stringWithFormat: @"mlmodels/%@", name];
    NSURL* modelURL = [self urlForResource: resource ofType: @"mlmodel"];
    
    if (!modelURL) {
        AssertFalse(mustExist);
        return nil;
    }
    
    __block MLModel* mlmodel;
    [self ignoreException: ^{
        NSError* error;
        NSURL* compiledModelURL = [MLModel compileModelAtURL: modelURL error: &error];
        AssertNotNil(compiledModelURL, @"Error when compiling model %@: %@", name, error);
        
        mlmodel = [MLModel modelWithContentsOfURL: compiledModelURL error: &error];
        AssertNotNil(mlmodel, @"Error when creating a model %@: %@", compiledModelURL.absoluteURL, error);
    }];
    
    return mlmodel;
}


- (CBLCoreMLPredictiveModel*) model: (NSString*)name mustExist: (BOOL)mustExist {
    MLModel* mlmodel = [self coreMLModel: name mustExist: mustExist];
    return mlmodel ? [[CBLCoreMLPredictiveModel alloc] initWithMLModel: mlmodel] : nil;
}


- (void) createMarsHabitatPricerModelDocuments: (NSArray*)documents {
    for (NSArray* values in documents) {
        CBLMutableDocument* doc = [self createDocument];
        if (values[0] != [NSNull null]) [doc setValue: values[0] forKey: @"solarPanels"];
        if (values[1] != [NSNull null]) [doc setValue: values[1] forKey: @"greenhouses"];
        if (values[2] != [NSNull null]) [doc setValue: values[2] forKey: @"size"];
        if (values.count > 3)           [doc setValue: values[3] forKey: @"expected_price"];
        [self saveDocument: doc];
    }
}


- (void) createDocumentWithImageAtPath: (NSString*)path {
    NSString* res = [path stringByDeletingPathExtension];
    NSString* ext = [path pathExtension];
    NSString* name = [res lastPathComponent];
    CBLMutableDocument* doc = [self createDocument];
    NSData* data = [self dataFromResource: res ofType: ext];
    NSString* type = [[ext lowercaseString] isEqualToString: @"jpg"] ? @"image/jpeg" : @"image/png";
    [doc setBlob: [[CBLBlob alloc] initWithContentType: type data: data] forKey: @"image"];
    [doc setString: name forKey: @"name"];
    [self saveDocument: doc];
}


- (void) testMarsHabitatPricerModel {
    CBLCoreMLPredictiveModel* model = [self model: @"Mars/MarsHabitatPricer" mustExist: YES];
    [CBLDatabase.prediction registerModel: model withName: @"MarsHabitatPricer"];
    
    // solarPanels, greenhouses, size, rounded expected_price
    NSArray* tests =
    @[
      @[@1.0, @1, @750, @1430],
      @[@1.5, @2, @1000, @3615],
      @[@3.0, @5, @2000, @11635]
      ];
    [self createMarsHabitatPricerModelDocuments: tests];
    
    NSDictionary* input = @{ @"solarPanels": EXPR_PROP(@"solarPanels"),
                             @"greenhouses": EXPR_PROP(@"greenhouses"),
                             @"size": EXPR_PROP(@"size")};
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"expected_price"),
                                             SEL_EXPR(PREDICTION(@"MarsHabitatPricer", EXPR_VAL(input)))]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        double expectedPrice = [r doubleAtIndex: 0];
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        AssertEqual(round([pred doubleForKey: @"price"]), expectedPrice);
    }];
    AssertEqual(numRows, tests.count);
    
    [CBLDatabase.prediction unregisterModelWithName: @"MarsHabitatPricer"];
}


- (void) testInvalidInput {
    CBLCoreMLPredictiveModel* model = [self model: @"Mars/MarsHabitatPricer" mustExist: YES];
    [CBLDatabase.prediction registerModel: model withName: @"MarsHabitatPricer"];
    
    // solarPanels, greenhouses, size, rounded expected_price
    NSArray* tests =
    @[
      @[@1.0, @"1", @750],
      @[[NSNull null], @2, @1000],
      @[@3.0, @5, @2000, @11635]
      ];
    [self createMarsHabitatPricerModelDocuments: tests];
    
    NSDictionary* input = @{ @"solarPanels": EXPR_PROP(@"solarPanels"),
                             @"greenhouses": EXPR_PROP(@"greenhouses"),
                             @"size": EXPR_PROP(@"size")};
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"expected_price"),
                                             SEL_EXPR(PREDICTION(@"MarsHabitatPricer", EXPR_VAL(input)))]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        if (![r valueAtIndex: 0])
            AssertNil(pred);
        else {
            double expectedPrice = [r doubleAtIndex: 0];
            AssertEqual(round([pred doubleForKey: @"price"]), expectedPrice);
        }
    }];
    AssertEqual(numRows, tests.count);
    
    [CBLDatabase.prediction unregisterModelWithName: @"MarsHabitatPricer"];
}


// Note: Download MobileNet.mlmodel from https://developer.apple.com/documentation/vision/classifying_images_with_vision_and_core_ml
// and put it at Objective-C/Tests/Support/mlmodels/MobileNet
- (void) testMobileNetModel {
    CBLCoreMLPredictiveModel* model = [self model: @"MobileNet/MobileNet" mustExist: NO];
    if (!model)
        return;
    
    [CBLDatabase.prediction registerModel: model withName: @"MobileNet"];
    
    [self createDocumentWithImageAtPath: @"mlmodels/MobileNet/cat.jpg"];
    
    NSDictionary* input = @{ @"image": EXPR_PROP(@"image") };
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_EXPR(PREDICTION(@"MobileNet", EXPR_VAL(input)))]
                                     from: kDATA_SRC_DB];
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        CBLDictionary* pred = [r dictionaryAtIndex: 0];
        NSString* label = [[pred stringForKey: @"classLabel"] lowercaseString];
        Assert([label rangeOfString: @"cat"].location != NSNotFound);
        CBLDictionary* probs = [pred dictionaryForKey: @"classLabelProbs"];
        Assert(probs.count > 0);
    }];
    AssertEqual(numRows, 1);
    
    [CBLDatabase.prediction unregisterModelWithName: @"MobileNet"];
}


// Note: Download OpenFace.mlmodel from https://github.com/iwantooxxoox/Keras-OpenFace
// and put it at Objective-C/Tests/Support/mlmodels/OpenFace
- (void) testOpenFaceModel {
    CBLCoreMLPredictiveModel* model = [self model: @"OpenFace/OpenFace" mustExist: NO];
    if (!model)
        return;
    
    [CBLDatabase.prediction registerModel: model withName: @"OpenFace"];
    
    NSArray* faces = @[@"adams", @"lennon-3", @"carell", @"lennon-2", @"lennon-1"];
    for (NSString* face in faces) {
        NSString* path = [NSString stringWithFormat: @"mlmodels/OpenFace/%@.png", face];
        [self createDocumentWithImageAtPath: path];
    }
    
    // Query the finger print of each face:
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    NSDictionary* input = @{ @"data": EXPR_PROP(@"image") };
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"name"),
                                             SEL_EXPR(PREDICTION(@"OpenFace", EXPR_VAL(input)))]
                                     from: kDATA_SRC_DB];
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSString* name = [r stringAtIndex: 0];
        AssertNotNil(name);
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        CBLArray* output = [pred arrayForKey: @"output"];
        AssertNotNil(output);
        AssertEqual(output.count, 128);
        [result setObject: output forKey: name];
    }];
    AssertEqual(numRows, faces.count);
    
    // Query the euclidean distance between each face and lennon-1:
    NSMutableArray* names = [NSMutableArray array];
    CBLArray* lennon1 = [result objectForKey: @"lennon-1"];
    CBLQueryExpression* vector1 = [CBLQueryExpression parameterNamed: @"vectorParam"];
    CBLQueryExpression* vector2 = PREDICTION_VALUE(@"OpenFace", EXPR_VAL(input), @"output");
    CBLQueryExpression* distance = [CBLQueryFunction euclideanDistanceBetween: vector1
                                                                          and: vector2];
    q = [CBLQueryBuilder select: @[SEL_PROP(@"name"),
                                   SEL_EXPR(distance)]
                           from: kDATA_SRC_DB
                          where: nil
                        orderBy: @[[CBLQueryOrdering expression: distance]]];
    CBLQueryParameters* params = [[CBLQueryParameters alloc] init];
    [params setArray: lennon1 forName: @"vectorParam"];
    q.parameters = params;
    numRows = [self verifyQuery: q randomAccess: NO
                           test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSString* name = [r stringAtIndex: 0];
        AssertNotNil(name);
        [names addObject: name];
        AssertNotNil([r numberAtIndex: 1]);
        if ([name isEqualToString: @"lennon-1"])
            AssertEqual([r doubleAtIndex: 1], 0.0);
        else
            Assert([r doubleAtIndex: 1] >= 0);
    }];
    AssertEqual(numRows, faces.count);
    AssertEqualObjects(names, (@[@"lennon-1", @"lennon-2", @"lennon-3", @"carell", @"adams"]));
    
    [CBLDatabase.prediction unregisterModelWithName: @"OpenFace"];
}


- (void) testBasicDataConversion {
    NSDictionary* dictData = @{@"name": @"Daniel", @"number": @(1)};
    CBLMutableDictionary* dict = [[CBLMutableDictionary alloc] initWithData: dictData];

    // Value, MLFeatureType, non-null-returned?
    NSArray *tests = @[@[@(9),      @(MLFeatureTypeInt64),      @(YES)],
                       @[@"nine",   @(MLFeatureTypeInt64),      @(NO)],
                       @[@(20.0),   @(MLFeatureTypeDouble),     @(YES)],
                       @[@"twenty", @(MLFeatureTypeDouble),     @(NO)],
                       @[@"string", @(MLFeatureTypeString),     @(YES)],
                       @[@(1),      @(MLFeatureTypeString),     @(NO)],
                       @[dict,      @(MLFeatureTypeDictionary), @(YES)],
                       @[@"dict",   @(MLFeatureTypeDictionary), @(NO)],
                       ];
    
    for (NSArray* test in tests) {
        MLFeatureType type = [test[1] integerValue];
        BOOL notNull = [test[2] boolValue];
        MLFeatureValue* featureValue =
            [CBLCoreMLPredictiveModel featureValueFromValue: test[0] type: type];
        if (notNull) {
            AssertEqual(featureValue.type, type);
            id value = [CBLCoreMLPredictiveModel valueFromFeatureValue: featureValue];
            AssertEqualObjects(value, test[0]);
        } else {
            AssertNil(featureValue);
        }
    }
}


- (void) testMultiArrayDataConversion {
    NSArray* types = @[@(MLMultiArrayDataTypeDouble),
                       @(MLMultiArrayDataTypeFloat32),
                       @(MLMultiArrayDataTypeInt32)];
    
    NSArray* arrayData = @[@[@1, @2, @3],
                           @[@4, @5, @6],
                           @[@7, @8, @9]];
    
    for (NSNumber* type in types) {
        // CBLArray to MLMultiArray:
        CBLMutableArray* mArray = [[CBLMutableArray alloc] initWithData: arrayData];
        NSArray* shape =  @[@3, @3];
        MLFeatureValue* featureValue =
            [CBLCoreMLPredictiveModel multiArrayFeatureValueFromValue: mArray
                                                                shape: shape
                                                                 type: type.integerValue];
        AssertEqual(featureValue.type, MLFeatureTypeMultiArray);
        MLMultiArray* multiArray = featureValue.multiArrayValue;
        AssertNotNil(multiArray);
        AssertEqualObjects(multiArray.shape, shape);
        AssertEqual(multiArray.dataType, type.integerValue);
        
        // MLMultiArray to CBLArray
        CBLArray* array = [CBLCoreMLPredictiveModel arrayFromMultiArray: multiArray];
        AssertEqualObjects(arrayData, [array toArray]);
    }
}


- (void) testSequenceDataConversion {
    if (@available(macOS 10.14, iOS 12.0, *)) {
        NSArray* types = @[@(MLFeatureTypeInt64), @(MLFeatureTypeString)];
        NSArray* tests = @[@[@1, @2, @3, @4, @5], @[@"1", @"2", @"3", @"4", @"5"]];
        
        for (NSUInteger i = 0; i < types.count; i++) {
            MLFeatureType type = [types[i] integerValue];
            NSArray* data = tests[i];
            
            // CBLArray to Sequence:
            CBLMutableArray* mArray = [[CBLMutableArray alloc] initWithData: data];
            MLFeatureValue* featureValue =
            [CBLCoreMLPredictiveModel sequenceFeatureValueFromValue: mArray type: type];
            AssertEqual(featureValue.type, MLFeatureTypeSequence);
            MLSequence* sequence = featureValue.sequenceValue;
            AssertNotNil(sequence);
            NSArray* values = nil;
            if (type == MLFeatureTypeInt64) {
                values = [sequence int64Values];
            } else {
                values = [sequence stringValues];
            }
            AssertEqualObjects(values, data);
            
            // Sequence to CBLArray:
            CBLArray* array = [CBLCoreMLPredictiveModel arrayFromSequence: sequence];
            AssertNotNil(array);
            AssertEqualObjects([array toArray], data);
        }
    }
}


- (void) testPixelBufferDataConversion {
    NSData* data = [self dataFromResource: @"mlmodels/MobileNet/cat" ofType: @"jpg"];
    CIImage* image = [[CIImage alloc] initWithData: data];
    AssertNotNil(data);
    
    // CBLBlob to PixelBuffer
    CBLBlob* blob1 = [[CBLBlob alloc] initWithContentType: @"image/jpeg" data: data];
    CVPixelBufferRef pixelBuffer = [CBLCoreMLPredictiveModel pixelBufferFromBlob: blob1];
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    AssertEqual(image.extent.size.width, width);
    AssertEqual(image.extent.size.height, height);
    CVPixelBufferUnlockBaseAddress(pixelBuffer,0);
    
    // PixelBuffer to CBLBlob
    CBLBlob* blob2 = [CBLCoreMLPredictiveModel blobFromPixelBuffer: pixelBuffer];
    AssertNotNil(blob2);
    AssertEqualObjects(blob2.contentType, @"image/png");
}


@end
