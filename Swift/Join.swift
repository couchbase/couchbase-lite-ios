//
//  Join.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A Join component representing a single join clause in the query statement. */
public class Join {
    
    /** Create a JOIN (same as INNER JOIN) component with the given data source. 
        Use the returned On component to specify join conditions. */
    public static func join(_ datasource: DataSource) -> On {
        return On(datasource: datasource, type: .inner)
    }
    
    /** Create a LEFT JOIN (same as LEFT OUTER JOIN) component with the given data source. 
        Use the returned On component to specify join conditions. */
    public static func leftJoin(_ datasource: DataSource) -> On {
        return On(datasource: datasource, type: .leftOuter)
    }
    
    /** Create a LEFT OUTER JOIN component with the given data source.
        Use the returned On component to specify join conditions. */
    public static func leftOuterJoin(_ datasource: DataSource) -> On {
        return On(datasource: datasource, type: .leftOuter)
    }
    
    /** Create an INNER JOIN component with the given data source.
        Use the returned On component to specify join conditions. */
    public static func innerJoin(_ datasource: DataSource) -> On {
        return On(datasource: datasource, type: .inner)
    }
    
    /** Create an CROSS JOIN component with the given data source. 
        Use the returned On component to specify join conditions. */
    public static func crossJoin(_ datasource: DataSource) -> On {
        return On(datasource: datasource, type: .cross)
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

/** On component used for specifying join conditions. */
public final class On : Join {
    
    let datasource: DataSource
    
    let type: JoinType
    
    init(datasource: DataSource, type: JoinType) {
        self.datasource = datasource
        self.type = type
        super.init(impl: nil)
    }
    
    /** Specify join conditions from the given expression. */
    public func on(_ expression: Expression) -> Join {
        let impl: CBLQueryJoin;
        switch self.type {
        case .leftOuter:
            impl = CBLQueryJoin.leftOuterJoin(datasource.impl, on: expression.impl)
        case .cross:
            impl = CBLQueryJoin.cross(datasource.impl, on: expression.impl)
        default:
            impl = CBLQueryJoin.innerJoin(datasource.impl, on: expression.impl)
        }
        return Join(impl: impl)
    }
    
}
