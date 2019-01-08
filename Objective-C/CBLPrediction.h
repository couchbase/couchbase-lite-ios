//
//  CBLPrediction.h
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

#import <Foundation/Foundation.h>
@class CBLDictionary;

NS_ASSUME_NONNULL_BEGIN

/**
 PredictiveModel protocol that allows to integrate machine learning model into
 CBL Query via invoking the Function.prediction() function.
 */
@protocol CBLPredictiveModel <NSObject>

- (nullable CBLDictionary*) predict: (CBLDictionary*)input;

@end


/**
 The prediction model manager for registering and unregistering predictive models.
 */
@interface CBLPrediction : NSObject

/**
 Register a predictive model by the given name.

 @param model The predictive model.
 @param name The name of the predictive model.
 */
- (void) registerModel: (id<CBLPredictiveModel>)model withName: (NSString*)name;


/**
 Unregister the predictive model of the given name.

 @param name The name of the predictive model.
 */
- (void) unregisterModelWithName: (NSString*)name;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
