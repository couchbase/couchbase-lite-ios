//
//  Limit.swift
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


/// A Limit component represents the LIMIT clause of the query statement.
public final class Limit: Query  {
    
    // MARK: Internal
    
    init(query: Query, limit: ExpressionProtocol, offset: ExpressionProtocol?) {
        super.init()
        
        self.copy(query)
        self.limitImpl = CBLQueryLimit(limit.toImpl(), offset: offset != nil ? offset!.toImpl() : nil)
    }
    
}
