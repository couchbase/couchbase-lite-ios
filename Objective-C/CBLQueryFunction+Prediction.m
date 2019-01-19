//
//  CBLQueryFunction+Prediction.m
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

#import "CBLQueryFunction+Prediction.h"
#import "CBLFunctionExpression.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryPredictionFunction ()

- (instancetype) initWithModel: (NSString*)model input: (CBLQueryExpression*)input;

@end

NS_ASSUME_NONNULL_END

@implementation CBLQueryFunction (Prediction)

+ (CBLQueryPredictionFunction*) predictionUsingModel: (NSString*)model
                                               input: (CBLQueryExpression*)input
{
    CBLAssertNotNil(model);
    CBLAssertNotNil(input);
    return [[CBLQueryPredictionFunction alloc] initWithModel: model input: input];
}

@end

@implementation CBLQueryPredictionFunction {
    CBLQueryExpression* _model;
    CBLQueryExpression* _input;
}


- (instancetype) initWithModel: (NSString*)model input: (CBLQueryExpression*)input {
    self = [super initWithNone];
    if (self) {
        _model = [CBLQueryExpression string: model];
        _input = input;
    }
    return self;
}


- (CBLQueryExpression*) property: (NSString*)keyPath {
    CBLAssertNotNil(keyPath);
    
    keyPath = [NSString stringWithFormat: @".%@", keyPath];
    return [self predictionExpressionWithParams:
            @[_model, _input, [CBLQueryExpression string: keyPath]]];
}


- (id) asJSON {
    return [[self predictionExpressionWithParams: @[_model, _input]] asJSON];
}


- (CBLFunctionExpression*) predictionExpressionWithParams: (NSArray<CBLQueryExpression*>*)params {
    return [[CBLFunctionExpression alloc] initWithFunction: @"PREDICTION()" params: params];
}

@end
