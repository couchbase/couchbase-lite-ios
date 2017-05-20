//
//  ConflictResolver.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 5/19/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public struct Conflict {
    public var mine: ReadOnlyDocument {
        return _mine
    }
    
    public var theirs: ReadOnlyDocument {
        return _theirs
    }
    
    public var base: ReadOnlyDocument? {
        return _base
    }
    
    init(impl: CBLConflict) {
        _mine = ReadOnlyDocument(impl.mine)
        _theirs = ReadOnlyDocument(impl.theirs)
        
        if let base = impl.base {
            _base = ReadOnlyDocument(base)
        } else {
            _base = nil
        }
    }
    
    let _mine: ReadOnlyDocument
    let _theirs: ReadOnlyDocument
    let _base: ReadOnlyDocument?
}

public protocol ConflictResolver {
    func resolve(conflict: Conflict) -> ReadOnlyDocument?
}
