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
public final class CoreMLPredictiveModel : PredictiveModel {
    
    /// The model name used when registering the CoreMLPredictiveModel model to the Database.
    public var name: String {
        return _impl.name
    }
    
    /// The MLModel object.
    public var model: MLModel {
        return _impl.model
    }
    
    /// Initializes the CoreMLPredictiveModel with the given model name and the MLModel object.
    ///
    /// - Parameters:
    ///   - name: The model name.
    ///   - model: The MLModel object.
    public init(name: String, model: MLModel) {
        _impl = CBLCoreMLPredictiveModel.init(name: name, model: model)
    }
    
    /// Registers the CoreMLPredictiveModel object to the Database with the model name given when
    /// initializing the CoreMLPredictiveModel object so that the model will be available to use
    /// by the Predictive Query's Function.prediction() function.
    public func register() {
        Database.prediction.registerModel(self, withName: self.name)
    }
    
    /// Unregisters the CoreMLPredictiveModel from the Database.
    public func unregister() {
        Database.prediction.unregisterModel(withName: self.name)
    }
    
    // MARK: PredictiveModel
    
    /// Returns Core ML model prediction result. The method will be called by the query engine
    /// when invoking the Function.prediction() function inside a query or an index.
    public func predict(input: DictionaryObject) -> DictionaryObject? {
        let output = _impl.predict(input._impl as! CBLDictionary)
        return DataConverter.convertGETValue(output) as? DictionaryObject
    }
    
    // MARK: Internal
    
    private let _impl: CBLCoreMLPredictiveModel
    
}
