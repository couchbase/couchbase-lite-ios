//
//  Prediction.swift
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
/// PredictiveModel protocol that allows to integrate machine learning model into
/// CBL Query via invoking the Function.prediction() function.
public protocol PredictiveModel {
    
    /// The prediction callback called when invoking the Function.prediction() function
    /// inside a query or an index. The input dictionary object's keys and values will be
    /// corresponding to the 'input' dictionary parameter of theFunction.prediction() function.
    ///
    /// If the prediction callback cannot return a result, the prediction callback
    /// should return null value, which will be evaluated as MISSING.
    ///
    /// - Parameter input: The input dictionary.
    /// - Returns: The output dictionary.
    func predict(input: DictionaryObject) -> DictionaryObject?
    
}

/// ENTERPRISE EDITION ONLY.
///
/// Predictive model manager class for registering and unregistering predictive models.
public class Prediction {
    
    /// Register a predictive model by the given name.
    ///
    /// - Parameters:
    ///   - model: The predictive model.
    ///   - name: The name of the predictive model.
    public func registerModel(_ model: PredictiveModel, withName name: String) {
        CBLDatabase.prediction().registerModel(withName: name) { (input) -> CBLDictionary? in
            self.predict(withModel: model, input: input);
        }
    }
    
    
    /// Unregister a predictive model of the given name.
    ///
    /// - Parameter name: The name of the predictive model.
    public func unregisterModel(withName name: String) {
        CBLDatabase.prediction().unregisterModel(withName: name)
    }
    
    
    // MARK: Internal
    
    
    func predict(withModel model: PredictiveModel, input: CBLDictionary) -> CBLDictionary? {
        let inputDict = DataConverter.convertGETValue(input) as! DictionaryObject
        let outputDict = model.predict(input: inputDict)
        guard let output = DataConverter.convertSETValue(outputDict) else {
            return nil
        }
        
        if let dict = output as? CBLNewDictionary {
            return dict.toCBLDictionary()
        }
        
        return output as? CBLDictionary
    }
    
}
