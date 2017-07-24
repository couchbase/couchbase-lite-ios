//
//  ConflictResolver.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public struct Conflict {
    public let mine: ReadOnlyDocument
    public let theirs: ReadOnlyDocument
    public let base: ReadOnlyDocument?

    init(impl: CBLConflict) {
        mine = ReadOnlyDocument(impl.mine)
        theirs = ReadOnlyDocument(impl.theirs)
        base = impl.base.flatMap({ReadOnlyDocument($0)})
    }
}

public protocol ConflictResolver {
    func resolve(conflict: Conflict) -> ReadOnlyDocument?
}
