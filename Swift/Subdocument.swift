//
//  Subdocument.swift
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 2/17/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation

public class Subdocument : Properties {
    
    /** The subdocument's owning document. */
    public var document: Document? {
        return _subdocimpl.document?.swiftDocument
    }
    
    /** Checks whether the subdocument exists in the database or not. */
    public var exists: Bool { return _subdocimpl.exists }
    
    
    init(_ impl: CBLSubdocument) {
        _subdocimpl = impl
        super.init(impl)
        
        impl.swiftSubdocument = self
    }
    
    deinit {
        _subdocimpl.swiftSubdocument = nil
    }
    
    let _subdocimpl: CBLSubdocument
}

extension CBLSubdocument {
    private struct AssociatedKeys {
        static var SwiftSubdocument = "SwiftSubdocument"
    }
    
    var swiftSubdocument: Subdocument? {
        get {return objc_getAssociatedObject(self, &AssociatedKeys.SwiftSubdocument) as? Subdocument}
        set { objc_setAssociatedObject(self, &AssociatedKeys.SwiftSubdocument, newValue,
                                       objc_AssociationPolicy.OBJC_ASSOCIATION_ASSIGN)}
    }
}
