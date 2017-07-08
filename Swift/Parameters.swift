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
    
    /** Set the value to the query parameter referenced by the given name. A query parameter
        is defined by using the Expression's parameter(_ name: String) function. */
    public func set(_ value: Any?, forName name: String) {
        if params == nil {
            params = [:]
        }
        params![name] = value
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
