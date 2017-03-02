//
//  Subdocument.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public class Subdocument : Properties, NSCopying {
    
    /** The subdocument's owning document. */
    public var document: Document? {
        return _subdocimpl.document?.swiftDocument as? Document
    }
    
    /** Checks whether the subdocument exists in the database or not. */
    public var exists: Bool { return _subdocimpl.exists }
    
    public convenience init() {
        self.init(CBLSubdocument())
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let subdoc = Subdocument()
        subdoc.properties = self.properties
        return subdoc
    }
    
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
