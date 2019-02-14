//
//  CBLCoreMLPredictiveModel.m
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
#import "CBLCoreMLPredictiveModel+Internal.h"
#import "CBLBlob.h"
#import "CBLDatabase+Prediction.h"
#import "CBLDictionary.h"
#import "CBLMutableArray.h"
#import "CBLMutableDictionary.h"

#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>

#define kCBLMayUseVisionModel YES
#define kCBLMaxVisionPredictedProbabilities 10

@implementation CBLCoreMLPredictiveModel {
    MLModel* _model;
    VNCoreMLModel* _vnModel;
    NSString* _vnFeatureName;
}

- (instancetype) initWithMLModel: (MLModel*)model {
    self = [super init];
    if (self) {
        _model = model;
        [self setupVisionModel];
    }
    return self;
}


- (void) setupVisionModel {
    if (!kCBLMayUseVisionModel)
        return;
        
    MLModelDescription* desc = _model.modelDescription;
    NSDictionary<NSString*, MLFeatureDescription*>* inputSpecs = desc.inputDescriptionsByName;
    NSDictionary<NSString*, MLFeatureDescription*>* outputSpecs = desc.outputDescriptionsByName;
    
    // Use Vision Model when there is single input and the input type is image:
    if (inputSpecs.count == 1 && inputSpecs.allValues[0].type == MLFeatureTypeImage) {
        NSError* error;
        _vnModel = [VNCoreMLModel modelForMLModel: _model error: &error];
        if (!_vnModel) {
            CBLWarn(Query, @"Cannot create vision model from the model: %@. "
                            "The regular MLModel will be used instead.", error);
            return;
        }
        
        BOOL isSupported = (desc.predictedFeatureName || outputSpecs.count == 1);
        if (isSupported) {
            _vnFeatureName = inputSpecs.allKeys[0];
        } else {
            CBLWarn(Query, @"Vision models that returns multiple VNCoreMLFeatureValueObservation "
                            "or VNPixelBufferObservation are not supported. The regular MLModel will "
                            "be used instead.");
            _vnModel = nil;
        }
    }
}


#pragma mark - CBLPredictiveModel


- (nullable CBLDictionary*) predict: (CBLDictionary*)input {
    if (_vnModel)
        return [self predictUsingVNModel: input];
    else
        return [self predictUsingMLModel: input];
}


- (nullable CBLDictionary*) predictUsingMLModel: (CBLDictionary*)input {
    id spec = _model.modelDescription.inputDescriptionsByName;
    id<MLFeatureProvider> features = [self.class featuresFromDictionary: input spec: spec];
    if (!features)
        return nil;
    
    NSError* error;
    id<MLFeatureProvider> output = [_model predictionFromFeatures: features error: &error];
    if (!output)
        return nil;
    
    return [self.class dictionaryFromFeatures: output];
}


- (nullable CBLDictionary*) predictUsingVNModel: (CBLDictionary*)input {
    assert(_vnModel != nil && _vnFeatureName != nil);
    
    CBLBlob* blob = [input valueForKey: _vnFeatureName];
    if (!blob) {
        CBLWarn(Query, @"Cannot find blob input for vision feature named %@", _vnFeatureName);
        return nil;
    }
    
    // Process the model:
    NSError* error;
    VNCoreMLRequest* request = [[VNCoreMLRequest alloc] initWithModel: _vnModel];
    VNImageRequestHandler* handler =
        [[VNImageRequestHandler alloc] initWithData: blob.content options: @{}];
    if (![handler performRequests: @[request] error: &error]) {
        CBLWarn(Query, @"Failed to process vision Core ML request for vision feature named %@ : %@",
                _vnFeatureName, error);
        return nil;
    }
    
    return [self predictionResultFromObservations: request.results];
}


- (CBLDictionary*) predictionResultFromObservations: (NSArray*)observations {
    if (observations.count == 0)
        return nil;
    
    // See https://developer.apple.com/documentation/vision/vncoremlrequest for
    // the information about the VNObservation results:
    NSString* predictedFeatureName = _model.modelDescription.predictedFeatureName;
    if (predictedFeatureName) {
        CBLMutableDictionary* result = [[CBLMutableDictionary alloc] init];
        
        // Predicted Feature:
        VNClassificationObservation* top = observations[0];
        [result setValue: top.identifier forKey: predictedFeatureName];
        
        // Predicted Probabilities:
        NSString* predictedProbsName = _model.modelDescription.predictedProbabilitiesName;
        if (predictedProbsName) {
            CBLMutableDictionary* probs = [[CBLMutableDictionary alloc] init];
            int count = 0;
            for (VNClassificationObservation* o in observations) {
                [probs setFloat: o.confidence forKey: o.identifier];
                if (++count == kCBLMaxVisionPredictedProbabilities)
                    break;
            }
            [result setDictionary: probs forKey: predictedProbsName];
        }
        return result;
    } else {
        // Note: Only one output is currently supported as there are no ways to map the observation
        // outputs (Array) to MLModel outputs (Dictionary) when the outputs are multiple.
        id value = nil;
        MLModelDescription* desc = _model.modelDescription;
        NSArray<NSString*>* outputKeys = desc.outputDescriptionsByName.allKeys;
        if (outputKeys.count == 1 && observations.count == 1) { // Make sure that there is only one
            VNObservation* o = observations[0];
            if ([o isKindOfClass: VNCoreMLFeatureValueObservation.class]) {
                MLFeatureValue* featureValue = ((VNCoreMLFeatureValueObservation*)o).featureValue;
                value = [self.class valueFromFeatureValue: featureValue];
            } else if ([o isKindOfClass: VNPixelBufferObservation.class]) {
                // Make sure output type is image
                if (desc.outputDescriptionsByName.allValues[0].type == MLFeatureTypeImage) {
                    CVPixelBufferRef pixel = ((VNPixelBufferObservation*)o).pixelBuffer;
                    value = [self.class blobFromPixelBuffer: pixel];
                }
            }
        }
        
        if (!value)
            return nil;
        
        CBLMutableDictionary* result = [[CBLMutableDictionary alloc] init];
        [result setValue: value forKey: outputKeys[0]];
        return result;
    }
}


#pragma mark - CBLDictionary to Features Conversion


+ (id<MLFeatureProvider>) featuresFromDictionary: (CBLDictionary*)dictionary
                                            spec: (NSDictionary<NSString*, MLFeatureDescription*>*)spec {
    NSMutableDictionary* dict = [[NSMutableDictionary alloc] initWithCapacity: spec.count];
    for (NSString* key in spec) {
        MLFeatureDescription* desc = spec[key];
        id value = [dictionary valueForKey: key];
        if (!value) {
            if (desc.optional)
                continue;
            CBLWarn(Query, @"The value of the non-optional input key (%@) is missing.", key);
            return nil;
        }
        
        BOOL isSequenceValue = NO;
        MLFeatureType sequenceType = MLFeatureTypeInvalid;
        if (@available(macOS 10.14, iOS 12.0, *)) {
            isSequenceValue = (desc.type == MLFeatureTypeSequence);
            sequenceType = desc.sequenceConstraint.valueDescription.type;
        }
        
        MLFeatureValue* featureValue;
        if (isSequenceValue) {
            if (@available(macOS 10.14, iOS 12.0, *)) {
                featureValue = [self.class sequenceFeatureValueFromValue: value type: sequenceType];
            }
        } else if (desc.type == MLFeatureTypeMultiArray) {
            MLMultiArrayConstraint* constraint = desc.multiArrayConstraint;
            featureValue = [self.class multiArrayFeatureValueFromValue: value
                                                                 shape: constraint.shape
                                                                  type: constraint.dataType] ;
        } else {
            featureValue = [self.class featureValueFromValue: value type: desc.type];
        }
        
        if (!featureValue) {
            CBLWarn(Query, @"Cannot convert the value of %@ key.", key);
            return nil;
        }
        [dict setObject: featureValue forKey: key];
    }
    
    NSError* error;
    MLDictionaryFeatureProvider* provider =
        [[MLDictionaryFeatureProvider alloc] initWithDictionary: dict error: &error];
    if (!provider) {
        CBLWarn(Query, @"Error when creating a dictionary feature provider: %@", error);
    }
    return provider;
}


+ (MLFeatureValue*) featureValueFromValue: (id)value type: (MLFeatureType)type {
    switch (type) {
        case MLFeatureTypeInt64: {
            NSNumber* num = $castIf(NSNumber, value);
            return num ? [MLFeatureValue featureValueWithInt64: [num longLongValue]] : nil;
        }
        case MLFeatureTypeDouble: {
            NSNumber* num = $castIf(NSNumber, value);
            return num ? [MLFeatureValue featureValueWithDouble: [num doubleValue]] : nil;
        }
        case MLFeatureTypeString: {
            NSString* str = $castIf(NSString, value);
            return str ? [MLFeatureValue featureValueWithString: str] : nil;
        }
        case MLFeatureTypeDictionary: {
            CBLDictionary* dict = $castIf(CBLDictionary, value);
            if (!dict)
                return nil;
            NSError* error;
            MLFeatureValue* dictValue = [MLFeatureValue featureValueWithDictionary:
                                         [dict toDictionary] error: &error];
            if (!dictValue) {
                CBLWarn(Query, @"Error when creating a dictionary feature value: %@", error);
            }
            return dictValue;
        }
        case MLFeatureTypeImage: {
            CBLBlob* blob = $castIf(CBLBlob, value);
            if (!blob)
                return nil;
            CVPixelBufferRef pixel = [self.class pixelBufferFromBlob: blob];
            if (pixel == NULL)
                return nil;
            return [MLFeatureValue featureValueWithPixelBuffer: pixel];
        }
        default:
            return nil;
    }
}


+ (MLFeatureValue*) sequenceFeatureValueFromValue: (id)value type: (MLFeatureType)type
API_AVAILABLE(macos(10.14), ios(12.0))
{
    CBLArray* cblArray = $castIf(CBLArray, value);
    if (!cblArray)
        return nil;
    
    NSArray* array = [cblArray toArray];
    switch (type) {
        case MLFeatureTypeInt64:
            return [MLFeatureValue featureValueWithSequence:
                    [MLSequence sequenceWithInt64Array: array]];
        case MLFeatureTypeString:
            return [MLFeatureValue featureValueWithSequence:
                    [MLSequence sequenceWithStringArray: array]];
        default:
            return nil;
    }
}


+ (MLFeatureValue*) multiArrayFeatureValueFromValue: (id)value
                                              shape: (NSArray<NSNumber*>*)shape
                                               type: (MLMultiArrayDataType)type
{
    CBLArray* array = $castIf(CBLArray, value);
    if (!array)
        return nil;
    
    if (shape.count == 0)
        return nil;
    
    id mArray = [self.class multiArrayFromArray: array shape: shape type: type];
    return mArray != nil ? [MLFeatureValue featureValueWithMultiArray: mArray] : nil;
}


+ (MLMultiArray*) multiArrayFromArray: (CBLArray*)array
                                shape: (NSArray<NSNumber*>*)shape
                                 type: (MLMultiArrayDataType)type
{
    NSError* error;
    MLMultiArray* multiArray = [[MLMultiArray alloc] initWithShape: shape
                                                          dataType: type
                                                             error: &error];
    if (!multiArray) {
        CBLWarn(Query, @"Error when creating a multi array of type %ld and shape %@ : %@",
                (long)type, shape, error);
    }
    
    NSMutableArray* keys = [NSMutableArray arrayWithCapacity: shape.count];
    BOOL success = [self.class setValueToMultiArray: multiArray
                                          fromArray: array
                                          dimension: 0
                                             atKeys: keys];
    return success ? multiArray : nil;
}


+ (BOOL) setValueToMultiArray: (MLMultiArray*)multiArray
                    fromArray: (CBLArray*)array
                    dimension: (NSUInteger)dimension
                       atKeys: (NSMutableArray<NSNumber*>*)keys
{
    if (!array)
        return NO; // no data
    
    BOOL isValue = (dimension == multiArray.shape.count - 1);
    NSUInteger itemCount = multiArray.shape[dimension].unsignedIntegerValue;
    
    if (array.count != itemCount)
        return NO; // item count not matched
    
    for (NSUInteger i = 0; i < itemCount; i++) {
        [keys addObject: @(i)];
        if (isValue) {
            NSNumber* number = [array numberAtIndex: i];
            if (!number)
                return NO; // wrong data type
            multiArray[keys] = number;
        } else {
            BOOL success = [self.class setValueToMultiArray: multiArray
                                                  fromArray: [array arrayAtIndex: i]
                                                  dimension: dimension + 1
                                                     atKeys: keys];
            if (!success)
                return NO;
        }
        [keys removeLastObject];
    }
    
    return YES;
}


+ (CVPixelBufferRef) pixelBufferFromBlob: (CBLBlob*)blob {
    if (!([blob.contentType isEqualToString: @"image/jpeg"] ||
          [blob.contentType isEqualToString: @"image/png"])) {
        CBLWarn(Query, @"Cannot create a pixel buffer from a blob of type %@", blob.contentType);
        return NULL;
    }
    
    CIImage* image = [[CIImage alloc] initWithData: blob.content];
    CVPixelBufferRef pixelBuffer = NULL;
    CGSize size = image.extent.size;
    
    CFDictionaryRef attrs = (__bridge CFDictionaryRef)
    @{ (__bridge NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
       (__bridge NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES };
    
    // Limitation: Only support ARGB now:
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          (size_t)size.width,
                                          (size_t)size.height,
                                          kCVPixelFormatType_32ARGB,
                                          attrs,
                                          &pixelBuffer);
    if (status != kCVReturnSuccess) {
        CBLWarn(Query, @"Failed to create a pixel buffer of size W: %f and H: %f",
                size.width, size.height);
        return NULL;
    }
    
    [[CIContext context] render: image toCVPixelBuffer: pixelBuffer];
    return pixelBuffer;
}


#pragma mark - Features to CBLDictionary Conversion


+ (CBLDictionary*) dictionaryFromFeatures: (id<MLFeatureProvider>)features {
    CBLMutableDictionary* output = [[CBLMutableDictionary alloc] init];
    for (NSString* name in [features featureNames]) {
        MLFeatureValue* featureValue = [features featureValueForName: name];
        id value = [self.class valueFromFeatureValue: featureValue];
        if (value)
            [output setValue: value forKey: name];
    }
    return output;
}


+ (id) valueFromFeatureValue: (MLFeatureValue*)featureValue {
    if (featureValue) {
        MLFeatureType type = featureValue.type;
        switch (type) {
            case MLFeatureTypeInt64:
                return [NSNumber numberWithLongLong: featureValue.int64Value];
            case MLFeatureTypeDouble:
                return [NSNumber numberWithDouble: featureValue.doubleValue];
            case MLFeatureTypeString:
                return featureValue.stringValue;
            case MLFeatureTypeDictionary:
                return [[CBLMutableDictionary alloc] initWithData: featureValue.dictionaryValue];
            case MLFeatureTypeMultiArray:
                return [self.class arrayFromMultiArray: featureValue.multiArrayValue];
            case MLFeatureTypeImage:
                return [self.class blobFromPixelBuffer: featureValue.imageBufferValue];
                break;
            default:
                if (@available(iOS 12.0, macOS 10.14, *)) {
                    if (type == MLFeatureTypeSequence)
                        return [self.class arrayFromSequence: featureValue.sequenceValue];
                }
        }
    }
    return nil;
}


+ (CBLArray*) arrayFromSequence: (MLSequence*)sequence API_AVAILABLE(macos(10.14), ios(12.0)) {
    if (!sequence)
        return nil;
    
    switch(sequence.type) {
        case MLFeatureTypeInt64:
            return [[CBLMutableArray alloc] initWithData: sequence.int64Values];
        case MLFeatureTypeString:
            return [[CBLMutableArray alloc] initWithData: sequence.stringValues];
        default:
            return nil;
    }
}


+ (CBLArray*) arrayFromMultiArray: (MLMultiArray*)multiArray {
    if (multiArray.shape.count == 0)
        return nil;
    return [self.class arrayFromMultiArray: multiArray dimension: 0 data: multiArray.dataPointer];
}


+ (CBLArray*) arrayFromMultiArray: (MLMultiArray*)array
                        dimension: (NSUInteger)dimension
                             data: (const uint8_t*)data
{
    MLMultiArrayDataType dataType = array.dataType;
    NSUInteger stride = array.strides[dimension].unsignedIntegerValue;
    
    NSUInteger offset = 0;
    switch (dataType) {
        case MLMultiArrayDataTypeInt32:
            offset = stride * sizeof(uint32_t);
            break;
        case MLMultiArrayDataTypeFloat32:
            offset = stride * sizeof(float);
            break;
        case MLMultiArrayDataTypeDouble:
            offset = stride * sizeof(double);
            break;
    }
    
    BOOL isValue = (dimension == array.shape.count - 1);
    NSUInteger itemCount = array.shape[dimension].unsignedIntegerValue;
    CBLMutableArray* outArray = [[CBLMutableArray alloc] init];
    for (NSUInteger i = 0; i < itemCount; i++) {
        if (isValue) {
            NSNumber* number = nil;
            switch (dataType) {
                case MLMultiArrayDataTypeInt32:
                    number = [NSNumber numberWithUnsignedInt: *(uint32_t*)data];
                    break;
                case MLMultiArrayDataTypeFloat32:
                    number = [NSNumber numberWithFloat: *(float*)data];
                    break;
                case MLMultiArrayDataTypeDouble:
                    number = [NSNumber numberWithDouble: *(double*)data];
                    break;
            }
            if (number)
                [outArray addNumber: number];
        } else {
            [outArray addArray: [self.class arrayFromMultiArray: array
                                                      dimension: dimension + 1
                                                           data: data]];
        }
        data += offset;
    }
    return outArray;
}


+ (CBLBlob*) blobFromPixelBuffer: (CVPixelBufferRef)pixel {
    CIImage* image = [CIImage imageWithCVImageBuffer: pixel];
    CGImageRef cgImage = [[CIContext context] createCGImage: image fromRect: image.extent];
    NSMutableData* data = [NSMutableData data];
    CGImageDestinationRef destination =
    CGImageDestinationCreateWithData((CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(destination, cgImage, nil);
    CGImageDestinationFinalize(destination);
    CGImageRelease(cgImage);
    CFRelease(destination);
    return [[CBLBlob alloc] initWithContentType: @"image/png" data: data];
}

@end
