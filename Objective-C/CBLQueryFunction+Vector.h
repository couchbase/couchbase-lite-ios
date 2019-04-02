//
//  CBLQueryFunction+Vector.h
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

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Vector Comparison

@interface CBLQueryFunction (Vector)

/**
 ENTERPRISE EDITION ONLY
 
 Creates a function that returns the euclidean distance between the two input vectors.
 The result is a non-negative floating-point number. The expression1 and expression2 must be
 arrays of numbers, and must be the same length.

 @param expression1 The expression evaluated to an arrays of numbers.
 @param expression2 The expression evaluated to an arrays of numbers.
 @return The euclient distance between two given input vectors.
 */
+ (CBLQueryExpression*) euclideanDistanceBetween: (CBLQueryExpression*)expression1
                                             and: (CBLQueryExpression*)expression2;

/**
 ENTERPRISE EDITION ONLY
 
 Creates a function that returns the squared euclidean distance between the two input vectors.
 The result is a non-negative floating-point number. The expression1 and expression2 must be
 arrays of numbers, and must be the same length.

 @param expression1 The expression evaluated to an arrays of numbers.
 @param expression2 The expression evaluated to an arrays of numbers.
 @return The squared euclient distance between two given input vectors.
 */
+ (CBLQueryExpression*) squaredEuclideanDistanceBetween: (CBLQueryExpression*)expression1
                                                    and: (CBLQueryExpression*)expression2;

/**
 ENTERPRISE EDITION ONLY
 
 Creates a function that returns the cosine distance which one minus the cosine similarity
 between the two input vectors. The result is a floating-point number ranges from −1.0 to 1.0.
 The expression1 and expression2 must be arrays of numbers, and must be the same length.

 @param expression1 The expression evaluated to an arrays of numbers.
 @param expression2 The expression evaluated to an arrays of numbers.
 @return The cosine distance between two given input vectors.
 */
+ (CBLQueryExpression*) cosineDistanceBetween: (CBLQueryExpression*)expression1
                                          and: (CBLQueryExpression*)expression2;

@end

NS_ASSUME_NONNULL_END
