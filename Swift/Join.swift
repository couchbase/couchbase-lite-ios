//
//  Join.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/29/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/// Join component representing a JOIN clause in the query statement.
public protocol JoinProtocol {
    
}

/// Join ON clause used for specifying join conditions.
public protocol JoinOnProtocol: JoinProtocol {
    
    /// Specify join conditions from the given expression.
    ///
    /// - Parameter expression: The Expression object specifying the join conditions.
    /// - Returns: The Join object that represents a single JOIN clause of the query.
    func on(_ expression: ExpressionProtocol) -> JoinProtocol
    
}

/// Join factory.
public class Join {
    
    /// Create a JOIN (same as INNER JOIN) component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func join(_ datasource: DataSourceProtocol) -> JoinOnProtocol {
        return JoinOn(datasource: datasource, type: .inner)
    }
    
    
    /// Create a LEFT JOIN (same as LEFT OUTER JOIN) component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func leftJoin(_ datasource: DataSourceProtocol) -> JoinOnProtocol {
        return JoinOn(datasource: datasource, type: .leftOuter)
    }
    
    
    /// Create a LEFT OUTER JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func leftOuterJoin(_ datasource: DataSourceProtocol) -> JoinOnProtocol {
        return JoinOn(datasource: datasource, type: .leftOuter)
    }
    
    
    /// Create an INNER JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func innerJoin(_ datasource: DataSourceProtocol) -> JoinOnProtocol {
        return JoinOn(datasource: datasource, type: .inner)
    }
    
    
    /// Create an CROSS JOIN component with the given data source.
    /// Use the returned On component to specify join conditions.
    ///
    /// - Parameter datasource: The DataSource object of the JOIN clause.
    /// - Returns: The On object used for specifying join conditions.
    public static func crossJoin(_ datasource: DataSourceProtocol) -> JoinProtocol {
        return QueryJoin(impl: CBLQueryJoin.cross(datasource.toImpl()))
    }
}

/* internal */ enum JoinType {
    case inner, leftOuter
}

/* internal */ class QueryJoin: JoinProtocol {
    
    let impl: CBLQueryJoin
    
    init(impl: CBLQueryJoin) {
        self.impl = impl
    }
    
    func toImpl() -> CBLQueryJoin {
        return self.impl
    }
    
    static func toImpl(joins: [JoinProtocol]) -> [CBLQueryJoin] {
        var joinsImpl: [CBLQueryJoin] = []
        for o in joins {
            joinsImpl.append(o.toImpl())
        }
        return joinsImpl;
    }
    
}

/* internal */ class JoinOn : QueryJoin, JoinOnProtocol {
    
    let datasource: DataSourceProtocol
    
    let type: JoinType
    
    init(datasource: DataSourceProtocol, type: JoinType) {
        self.datasource = datasource
        self.type = type
        
        let impl: CBLQueryJoin;
        switch self.type {
        case .leftOuter:
            impl = CBLQueryJoin.leftOuterJoin(datasource.toImpl(), on: nil)
        default:
            impl = CBLQueryJoin.innerJoin(datasource.toImpl(), on: nil)
        }
        super.init(impl: impl)
    }
    
    /// Specify join conditions from the given expression.
    ///
    /// - Parameter expression: The Expression object specifying the join conditions.
    /// - Returns: The Join object that represents a single JOIN clause of the query.
    public func on(_ expression: ExpressionProtocol) -> JoinProtocol {
        let impl: CBLQueryJoin;
        switch self.type {
        case .leftOuter:
            impl = CBLQueryJoin.leftOuterJoin(datasource.toImpl(), on: expression.toImpl())
        default:
            impl = CBLQueryJoin.innerJoin(datasource.toImpl(), on: expression.toImpl())
        }
        return QueryJoin(impl: impl)
    }
    
}

extension JoinProtocol {
    func toImpl() -> CBLQueryJoin {
        if let o = self as? QueryJoin {
            return o.toImpl()
        }
        fatalError("Unsupported join.")
    }
}
