//
//  HavingRouter.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation


/// HavingRouter for creating and chaning a query HAVING clause.
protocol HavingRouter {
    
    /// Creates and chain a Having object for filtering the aggregated values
    /// from the the GROUP BY clause.
    ///
    /// - Parameter expression: The expression.
    /// - Returns: The Having object that represents the HAVING clause of the query.
    func having(_ expression: ExpressionProtocol) -> Having
    
}
