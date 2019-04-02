//
//  CBLPredictiveIndex.h
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc. All rights reserved.
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

#import <Foundation/Foundation.h>
#import "CBLIndex.h"

NS_ASSUME_NONNULL_BEGIN


/**
 ENTERPRISE EDITION ONLY : UNCOMMITTED
 
 The predictive index used for querying with prediction function. The predictive index
 is different from the normal index in that the predictive index will cache the prediction
 result along with creating the value index of the prediction output properties.
 
 The PredictiveIndex can be created by using IndexBuilder's predictiveIndex() function.
 If the prediction output properties are not specified, the predictive index will only cache
 the predictive result so that the predictive model will not be called again after indexing.
 */
@interface CBLPredictiveIndex : CBLIndex

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
