//
//  GroupBy.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 7/5/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** A GroupBy represents a query GROUP BY statement to group the query result.
    The GROUP BY statement is normally used with aggregate functions (AVG, COUNT, MAX, MIN, SUM)
    to aggregate the group of the values. */
public class GroupBy: Query, HavingRouter, OrderByRouter {
    /** */
    public static func expression(_ expression: Expression) -> GroupBy {
        let gropuBy = CBLQueryGroupBy.expression(expression.impl)
        return GroupBy(impl: gropuBy)
    }
    
    /** Create and chain a HAVING component for filtering the aggregated values 
        from the the GROUP BY clause. */
    public func having(_ expression: Expression) -> Having {
        return Having(query: self, impl: expression.impl)
    }
    
    /** Create and chain ORDER BY components for specifying the order of the query result. */
    public func orderBy(_ orders: OrderBy...) -> OrderBy {
        return OrderBy(query: self, impl: OrderBy.toImpl(orders: orders))
    }
    
    // MARK: Internal
    
    init(query: Query, impl: [CBLQueryGroupBy]) {
        super.init()
        self.copy(query)
        self.groupByImpl = impl
    }
    
    init(impl: CBLQueryGroupBy) {
        super.init()
        self.groupByImpl = [impl]
    }
    
    static func toImpl(groupBies: [GroupBy]) -> [CBLQueryGroupBy] {
        var impls: [CBLQueryGroupBy] = []
        for g in groupBies {
            for impl in g.groupByImpl! {
                impls.append(impl)
            }
        }
        return impls;
    }
}
