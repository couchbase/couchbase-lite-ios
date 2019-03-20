//
//  Function+Prediction.swift
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

import Foundation

/// ENTERPRISE EDITION ONLY.
///
/// PredictionFunction protocol that allows to create an expression that
/// refers to one of the properties of the prediction result dictionary.
public protocol PredictionFunction : ExpressionProtocol {
    
    /// Creates a property expression that refers to a property of the
    /// prediction result dictionary.
    ///
    /// - Parameter keyPath: The key path to the property.
    /// - Returns: The property expression referring to a property of the prediction dictionary result.
    func property(_ keyPath: String) -> ExpressionProtocol;
    
}

extension Function {
    
    // MARK: Prediction
    
    /// ENTERPRISE EDITION ONLY : DEVELOPER PREVIEW
    ///
    /// Creates prediction function with the given model name and input. When running a query with
    /// the prediction function, the corresponding predictive model registered to CouchbaseLite
    /// Database class will be called with the given input to predict the result.
    ///
    /// The prediction result returned by the predictive model will be in a form dictionary object.
    /// To create an expression that refers to a property in the prediction result,
    /// the property(_ keypath: String) method of the created PredictionFunction object
    /// can be used.
    ///
    /// - Parameters:
    ///   - model: The predictive model name registered to the CouchbaseLite Database.
    ///   - input: The expression evaluated to a dictionary.
    /// - Returns: A PredictionFunction object.
    public static func prediction(model: String,
                                  input: ExpressionProtocol) -> PredictionFunction
    {
        let prediction = CBLQueryFunction.prediction(usingModel: model, input: input.toImpl())
        return PredictionFunctionExpression(prediction)
    }
    
}

/// An internal class that implements PredictionFunction
class PredictionFunctionExpression : QueryExpression, PredictionFunction {

    func property(_ keyPath: String) -> ExpressionProtocol {
        let prediction = toImpl() as! CBLQueryPredictionFunction
        return QueryExpression(prediction.property(keyPath))
    }
    
}
