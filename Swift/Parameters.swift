//
//  Parameters.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Parameters object used for setting values to the query parameters defined in the query.
public final class Parameters {
    
    /// Gets a parameter's value.
    ///
    /// - Parameter name: The parameter name.
    /// - Returns: The parameter value.
    public func value(forName name: String) -> Any? {
        return self.params[name];
    }
    
    /// The builder for the Parameters.
    public final class Builder {
        
        /// Initializes the Parameters's builder.
        public init() {
            self.params = [:]
        }
        
        
        /// Initializes the Parameters's builder with the given parameters.
        ///
        /// - Parameter parameters: The parameters.
        public init(withParameters parameters: Parameters?) {
            self.params = parameters != nil ? parameters!.params : [:]
        }
        
        
        /// Set a boolean value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The boolean value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setBoolean(_ value: Bool, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set a date value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The date value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setDate(_ value: Date?, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set a double value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The double value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setDouble(_ value: Double, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set a float value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The float value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setFloat(_ value: Float, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set an int value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The int value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setInt(_ value: Int, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set an int64 value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The int64 value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setInt64(_ value: Int64, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set a String value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The String value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setString(_ value: String?, forName name: String) -> Self {
            return setValue(value, forName: name)
        }
        
        
        /// Set a value to the query parameter referenced by the given name. A query parameter
        /// is defined by using the Expression's parameter(_ name: String) function.
        ///
        /// - Parameters:
        ///   - value: The value.
        ///   - name: The parameter name.
        /// - Returns: The self object.
        @discardableResult public func setValue(_ value: Any?, forName name: String) -> Self {
            params[name] = value
            return self
        }
        
        
        /// Build a Parameters object with the current parameters.
        ///
        /// - Returns: The Parameters object.
        public func build() -> Parameters {
            return Parameters(withBuilder: self)
        }
        
        
        // MARK: Internal
        
        
        var params: Dictionary<String, Any>
    }
    
    
    // MARK: Internal
    
    
    let params: Dictionary<String, Any>
    
    
    init(withBuilder builder:Builder) {
        self.params = builder.params
    }
    
    
    func toImpl() -> CBLQueryParameters {
        let p = CBLQueryParameters { (builder) in
            for (name, value) in self.params {
                builder.setValue(value, forName: name)
            }
        }
        return p
    }
    
}
