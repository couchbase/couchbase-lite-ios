//
//  ConflictResolver.swift
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

/// The Conflict provides details about a conflict.
public struct Conflict {
    
    /// Mine version of the document.
    public let mine: Document
    
    /// Theirs version of the document.
    public let theirs: Document
    
    /// Base or common anchester version of the document.
    public let base: Document?

    init(impl: CBLConflict) {
        mine = Document(impl.mine)
        theirs = Document(impl.theirs)
        base = impl.base.flatMap({Document($0)})
    }
    
}

/// A protocol for an application-defined object that can resolve a conflict between two versions
/// of a document along with the base or the common ancester document if available. Called when saving
/// a document, when there is a a newer revision already in the database; and also when the
/// replicator pulls a remote revision that conflicts with a locally-saved revision.
public protocol ConflictResolver {
    
    /// Resolves the given conflict. Returning a nil document means giving up the conflict resolution
    /// and will result to a conflicting error returned when saving the document.
    ///
    /// - Parameter conflict: The conflict object.
    /// - Returns: The result document of the conflict resolution.
    func resolve(conflict: Conflict) -> Document?
    
}

class BridgingConflictResolver: NSObject, CBLConflictResolver {
    let _resovler: ConflictResolver
    
    init(resolver: ConflictResolver) {
        _resovler = resolver
    }
    
    public func resolve(_ conflict: CBLConflict) -> CBLDocument? {
        let resolved = _resovler.resolve(conflict: Conflict(impl: conflict))
        return resolved?._impl
    }
}

// A placeholder for using default conflict resolver defined in Objective-C
class DefaultConflictResolver: ConflictResolver {
    func resolve(conflict: Conflict) -> Document? {
        return nil;
    }
}
