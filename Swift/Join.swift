//
//  Join.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// A Join component representing a single JOIN clause in the query statement.
public class Join {
    
    /// Create a JOIN (same as INNER JOIN) component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func join(_ datasource: DataSource) -> JoinOn {
        return JoinOn(datasource: datasource, type: .inner)
    }
    
    
    /// Create a LEFT JOIN (same as LEFT OUTER JOIN) component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func leftJoin(_ datasource: DataSource) -> JoinOn {
        return JoinOn(datasource: datasource, type: .leftOuter)
    }
    
    
    /// Create a LEFT OUTER JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func leftOuterJoin(_ datasource: DataSource) -> JoinOn {
        return JoinOn(datasource: datasource, type: .leftOuter)
    }
    
    
    /// Create an INNER JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func innerJoin(_ datasource: DataSource) -> JoinOn {
        return JoinOn(datasource: datasource, type: .inner)
    }
    
    
    /// Create an CROSS JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func crossJoin(_ datasource: DataSource) -> Join {
        return Join(impl: CBLQueryJoin.cross(datasource.impl))
    }
    
    // MARK: Internal
    
    let impl: CBLQueryJoin?
    
    init(impl: CBLQueryJoin?) {
        self.impl = impl
    }
    
    static func toImpl(joins: [Join]) -> [CBLQueryJoin] {
        var joinsImpl: [CBLQueryJoin] = []
        for o in joins {
            if let impl = o.impl {
                joinsImpl.append(impl)
            }
        }
        return joinsImpl;
    }
    
}

/* internal */ enum JoinType {
    case inner, leftOuter, cross
}

/// On component used for specifying join conditions.
public final class JoinOn : Join {
    
    let datasource: DataSource
    
    let type: JoinType
    
    init(datasource: DataSource, type: JoinType) {
        self.datasource = datasource
        self.type = type
        super.init(impl: nil)
    }
    
    
    /// Specify join conditions from the given expression.
    ///
    /// - Parameter expression: The Expression object specifying the join conditions.
    /// - Returns: The Join object that represents a single JOIN clause of the query.
    public func on(_ expression: Expression) -> Join {
        let impl: CBLQueryJoin;
        switch self.type {
        case .leftOuter:
            impl = CBLQueryJoin.leftOuterJoin(datasource.impl, on: expression.impl)
        default:
            impl = CBLQueryJoin.innerJoin(datasource.impl, on: expression.impl)
        }
        return Join(impl: impl)
    }
    
}
