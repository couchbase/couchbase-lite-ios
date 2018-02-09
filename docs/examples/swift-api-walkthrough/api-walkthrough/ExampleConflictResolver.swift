//
//  ExampleConflictResolver.swift
//  api-walkthrough
//
//  Created by James Nocentini on 27/07/2017.
//  Copyright © 2017 couchbase. All rights reserved.
//

import Foundation
import CouchbaseLiteSwift

class ExampleConflictResolver: ConflictResolver {
    func resolve(conflict: Conflict) -> Document? {
        let base = conflict.base
        let mine = conflict.mine
        let theirs = conflict.theirs
        return theirs
    }
}
