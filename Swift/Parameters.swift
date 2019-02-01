//
//  Parameters.swift
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


/// Query parameters used for setting values to the query parameters defined in the query.
public class Parameters {
    
    /// Initializes the Parameters's builder.
    public convenience init() {
        self.init(parameters: nil, readonly: false)
    }
    
    /// Initializes the Parameters's builder with the given parameters.
    ///
    /// - Parameter parameters: The parameters.
    public convenience init(parameters: Parameters?) {
        self.init(parameters: parameters, readonly: false)
    }
    
    /// Gets a parameter's value.
    ///
    /// - Parameter name: The parameter name.
    /// - Returns: The parameter value.
    public func value(forName name: String) -> Any? {
        return self.params[name];
    }
    
    /// Set an ArrayObject value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The ArrayObject value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setArray(_ value: ArrayObject?, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a Blob value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The Blob value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setBlob(_ value: Blob?, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a boolean value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The boolean value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setBoolean(_ value: Bool, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a date value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The date value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setDate(_ value: Date?, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a DictionaryObject value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The DictionaryObject value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setDictionary(_ value: DictionaryObject?, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a double value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The double value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setDouble(_ value: Double, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a float value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The float value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setFloat(_ value: Float, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set an int value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The int value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setInt(_ value: Int, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set an int64 value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The int64 value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setInt64(_ value: Int64, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a String value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The String value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setString(_ value: String?, forName name: String) -> Parameters {
        return setValue(value, forName: name)
    }
    
    /// Set a value to the query parameter referenced by the given name. A query parameter
    /// is defined by using the Expression's parameter(_ name: String) function.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - name: The parameter name.
    /// - Returns: The self object.
    @discardableResult public func setValue(_ value: Any?, forName name: String) -> Parameters {
        checkReadOnly()
        params[name] = value
        return self
    }
    
    // MARK: Internal
    
    private let readonly: Bool
    
    var params: Dictionary<String, Any>
    
    init(parameters: Parameters?, readonly: Bool) {
        self.params = parameters != nil ? parameters!.params : [:]
        self.readonly = readonly
    }
    
    func checkReadOnly() {
        if self.readonly {
            fatalError("This parameters object is readonly.")
        }
    }
    
    func toImpl() -> CBLQueryParameters {
        let params = CBLQueryParameters()
        for (name, value) in self.params {
            params.setValue(DataConverter.convertSETValue(value), forName: name)
        }
        return params
    }
    
}
