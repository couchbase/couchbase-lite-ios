//
//  ValueExpression.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

/// Value Expression.
/* internal */ class ValueExpression: QueryExpression {
    init(value: Any?) {
        super.init(CBLQueryExpression.value(ValueExpression.convertValue(value)))
    }
    
    static func convertValue(_ value: Any?) -> Any? {
        switch value {
        case let v as [String: Any]:
            return ValueExpression.convertDictionary(v)
        case let v as [Any]:
            return ValueExpression.convertArray(v)
        case let v as ExpressionProtocol:
            return v.toImpl()
        default:
            return value
        }
    }
    
    static func convertDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            result[key] = ValueExpression.convertValue(value)!
        }
        return result
    }
    
    static func convertArray(_ array: [Any]) -> [Any] {
        var result: [Any] = [];
        for v in array {
            result.append(ValueExpression.convertValue(v)!)
        }
        return result
    }
}
