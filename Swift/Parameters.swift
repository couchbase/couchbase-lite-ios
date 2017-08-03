//
//  Parameters.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/7/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A Parameters object used for setting values to the query parameters defined in the query. */
public class Parameters {
    
    /** Set a boolean value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The boolean value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult  public func setBoolean(_ value: Bool, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    
    /** Set a date value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The date value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult  public func setDate(_ value: Date?, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    
    /** Set a double value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The double value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult public func setDouble(_ value: Double, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    
    /** Set a float value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The float value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult public func setFloat(_ value: Float, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    
    /** Set an integer value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The integer value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult public func setInteger(_ value: Int, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    
    /** Set a String value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function.
        - Parameter value: The String value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult public func setString(_ value: String?, forName name: String) -> Self {
        return setValue(value, forName: name)
    }
    
    /** Set a value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function. 
        - Parameter value: The value.
        - Parameter name: The parameter name.
        - Returns: The Parameters object. */
    @discardableResult public func setValue(_ value: Any?, forName name: String) -> Self {
        if params == nil {
            params = [:]
        }
        params![name] = value
        
        return self
    }
    
    // MARK: Internal
    
    var params: [String: Any]?
    
    init(params: Dictionary<String, Any>?) {
        self.params = params
    }
    
    func copy() -> Parameters {
        return Parameters(params: params)
    }
    
}
