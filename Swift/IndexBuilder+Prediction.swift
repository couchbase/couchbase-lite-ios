//
//  IndexBuilder+Prediction.swift
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

extension IndexBuilder {
    
    /// Create a predictive index with the given predictive model name, input specification to
    /// the predictive model, and the properties of the prediction result.
    ///
    /// The input given specification should be matched to the input specification given to the
    /// query prediction() function so that the predictive index can be matched and used in query.
    ///
    /// The predictive index is different from the normal index in that the predictive index will
    /// also cache the prediction result along with creating the value index of the specified
    /// properties. If the properties are not specified, the predictive index will only cache
    /// the prediction result so that the prediction model will not be called again after indexing.
    /// If multiple properties are specified, a compound value index will be created from the
    /// the given properties.
    ///
    /// - Parameters:
    ///   - model: The predictive model name.
    ///   - input: The input specification that should be matched with the input
    ///            specification given to the query prediction function.
    ///   - properties: The prediction result's properties to be indexed.
    /// - Returns: The predictive index.
    public static func predictiveIndex(model: String,
                                       input: ExpressionProtocol,
                                  properties: [String]? = nil) -> PredictiveIndex {
        return PredictiveIndex.init(model: model, input: input, properties: properties)
    }
    
}
