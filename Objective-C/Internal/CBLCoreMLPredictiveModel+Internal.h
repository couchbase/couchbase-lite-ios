//
//  CBLCoreMLPredictiveModel+Internal.h
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

#import "CBLCoreMLPredictiveModel.h"
@class CBLArray;
@class CBLBlob;

NS_ASSUME_NONNULL_BEGIN

/**
 For making these internal methods available for testing.
 */
@interface CBLCoreMLPredictiveModel ()

+ (nullable id) valueFromFeatureValue: (MLFeatureValue*)featureValue;

+ (nullable MLFeatureValue*) featureValueFromValue: (id)value type: (MLFeatureType)type;

+ (nullable MLFeatureValue*) multiArrayFeatureValueFromValue: (id)value
                                                       shape: (NSArray<NSNumber*>*)shape
                                                        type: (MLMultiArrayDataType)type;

+ (nullable CBLArray*) arrayFromMultiArray: (MLMultiArray*)multiArray;

+ (nullable MLFeatureValue*) sequenceFeatureValueFromValue: (id)value type: (MLFeatureType)type
  API_AVAILABLE(macos(10.14), ios(12.0));

+ (nullable CBLArray*) arrayFromSequence: (MLSequence*)sequence
  API_AVAILABLE(macos(10.14), ios(12.0));

+ (nullable CVPixelBufferRef) pixelBufferFromBlob: (CBLBlob*)blob;

+ (nullable CBLBlob*) blobFromPixelBuffer: (CVPixelBufferRef)pixel;

@end

NS_ASSUME_NONNULL_END
