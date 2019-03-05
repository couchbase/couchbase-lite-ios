//
//  CoreMLPredictiveModel.swift
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

import Foundation
import CoreML

/// CoreMLPredictiveModel is a Core ML based implementation of the PredictiveModel
/// protocol. Basically the CoreMLPredictiveModel used a Core ML model to return
/// prediction results.
///
/// CoreMLPredictiveModel automatically converts between Couchbase Lite data and Core ML
/// data when calling into the MLModel object to return prediction results. All Core ML
/// data types including Int64, Double, String, Dictionary, MultiArray, Image, and Sequence
/// are supported.
///
/// When the MLObject has a single input and the input type is Image, CoreMLPredictiveModel
/// will use Vision framework via the VNCoreMLModel to process the input image and call into
/// the MLModel object. The CoreMLPredictiveModel supports all VNObservation types including
/// VNClassificationObservation, VNCoreMLFeatureValueObservation, and VNPixelBufferObservation
/// as mentioned in https://developer.apple.com/documentation/vision/vncoremlrequest.

/// However there is a compatibility limitation when the VNCoreMLModel returns
/// VNCoreMLFeatureValueObservation or VNPixelBufferObservation results that the MLModel must
/// return a single output, otherwise the observation outputs cannot be mapped to the MLModel
/// outputs. When the VNCoreMLModel cannot be used to result the prediction result,
/// CoreMLPredictiveModel will fall back to use the MLModel instead.
///
/// When converting blob data to VNPixelBuffer for an input image, only ARGB pixel format
/// is currently supported. However this limitation is applied only when the VNCoreMLModel cannot
/// be used.
@available(macOS 10.13, iOS 11.0, *)
open class CoreMLPredictiveModel : PredictiveModel {
    
    /// Initializes the CoreMLPredictiveModel with the MLModel object.
    ///
    /// - Parameters:
    ///   - mlModel: The MLModel object.
    public init(mlModel: MLModel) {
        _impl = CBLCoreMLPredictiveModel(mlModel: mlModel)
    }
    
    /// Prediction output transformer.
    public var outputTransformer: ((DictionaryObject?) -> DictionaryObject?)?
    
    // MARK: PredictiveModel
    
    /// Makes prediction by using the Core ML model. The method will be called by the query engine
    /// when invoking the Function.prediction() function inside a query or an index.
    open func predict(input: DictionaryObject) -> DictionaryObject? {
        let prediction = _impl.predict(input._impl as! CBLDictionary)
        var output = DataConverter.convertGETValue(prediction) as? DictionaryObject
        if let transformer = self.outputTransformer {
            output = transformer(output)
        }
        return output;
    }
    
    // MARK: Internal
    
    private let _impl: CBLCoreMLPredictiveModel
    
}
