//
//  PredictiveIndex.swift
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

public final class PredictiveIndex: Index, CBLIndexConvertible {
    
    // MARK: Internal
    
    private let impl: CBLPredictiveIndex
    
    init(model: String, input: ExpressionProtocol, properties: [String]?) {
        self.impl = CBLIndexBuilder.predictiveIndex(withModel: model, input: input.toImpl(),
                                                   properties: properties)
    }
    
    func toImpl() -> CBLIndex {
        return self.impl as CBLIndex
    }
    
}
