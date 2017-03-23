//
//  Subdocument.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

/** Subdocument is a nested document with its own set of named properties. In JSON terms it's a 
 nested JSON Map object.
 Like Document, Subdocument is mutable, so you can make changes in-place. The difference is
 that a Subdocument doesn't have its own ID. It's not a first-class entity in the database,
 it's just a nested object within the document's JSON. It can't be saved individually; changes are
 persisted when you save its document.*/
public class Subdocument : Properties, NSCopying {
    
    /** The subdocument's owning document. */
    public var document: Document? {
        return _subdocimpl.document?.swiftDocument as? Document
    }
    
    /** Checks whether the subdocument exists in the database or not. */
    public var exists: Bool { return _subdocimpl.exists }
    
    /** Initialize a new subdocument */
    public convenience init() {
        self.init(CBLSubdocument())
    }
    
    /** Copy the current subdocument. */
    public func copy(with zone: NSZone? = nil) -> Any {
        let subdoc = Subdocument()
        subdoc.properties = self.properties
        return subdoc
    }
    
    // MARK: Internal
    
    init(_ impl: CBLSubdocument) {
        _subdocimpl = impl
        super.init(impl)
        
        _subdocimpl.swiftSubdocument = self
    }
    
    deinit {
        _subdocimpl.swiftSubdocument = nil
    }
    
    let _subdocimpl: CBLSubdocument
    
}
