//
//  ReplicatorChange.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 6/28/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/// ReplicatorChange contains the replicator status information.
public struct ReplicatorChange {
    
    /// The source replicator object.
    public let replicator: Replicator
    
    /// The replicator status.
    public let status: Replicator.Status
}
