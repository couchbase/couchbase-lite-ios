//
//  CBLQueryFunction+Prediction.h
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

#import "CBLQueryFunction.h"
#import "CBLQueryExpression.h"
@class CBLQueryPredictionFunction;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Prediction

@interface CBLQueryFunction (Prediction)

/**
 ENTERPRISE EDITION ONLY : UNCOMMITTED
 
 Creates prediction function with the given model name and input. When running a query with
 the prediction function, the corresponding predictive model registered to CBLDatabase class
 will be called with the given input to predict the result.
 
 The prediction result returned by the predictive model will be in a form dictionary object.
 To create an expression that refers to a property in the prediction result, the -property:
 method of the created CBLQueryPredictionFunction object can be used.

 @param model The predictive model name registered to the CouchbaseLite Database.
 @param input The expression evaluated to a dictionary.
 @return A CBLQueryPredictionFunction object.
 */
+ (CBLQueryPredictionFunction*) predictionUsingModel: (NSString*)model
                                               input: (CBLQueryExpression*)input;

@end

/**
 ENTERPRISE EDITION ONLY : UNCOMMITTED
 
 CBLQueryPredictionFunction that allows to create an expression that
 refers to one of the properties of the prediction result dictionary.
 */
@interface CBLQueryPredictionFunction : CBLQueryExpression


/**
 Creates a property expression that refers to a property of the prediction result dictionary.

 @param keyPath The key path to the property.
 @return The property expression referring to a property of the prediction dictionary result.
 */
- (CBLQueryExpression*) property: (NSString*)keyPath;

@end

NS_ASSUME_NONNULL_END
