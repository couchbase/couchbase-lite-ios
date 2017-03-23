//
//  Document.swift
//  CouchbaseLite
//
//  Created by Jens Alfke on 2/9/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

import Foundation


/** A Couchbase Lite document.
    A document has key/value properties like a Dictionary; their API is defined by the
    superclass Properties. To learn how to work with properties, see that class's documentation. */
public class Document : Properties {

    /** The document's ID. */
    public var documentID: String { return _docimpl.documentID }


    /** The document's owning database. */
    public let database: Database


    /** Is the document deleted? */
    public var isDeleted: Bool { return _docimpl.isDeleted }


    /** Checks whether the document exists in the database or not.
        If not, saving it will create it. */
    public var exists: Bool { return _docimpl.exists }


    /** Sequence number of the document in the database.
        This indicates how recently the document has been changed: every time any document is updated,
        the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
        property changes that means it's been changed (on-disk); and if one document's `sequence`
        is greater than another's, that means it was changed more recently. */
    public var sequence: UInt64 { return _docimpl.sequence }


    /** The conflict resolver, if any, specific to this document.
        If nil, the database's conflict resolver will be used. */
    public var conflictResolver: ConflictResolver? {
        get {return _docimpl.conflictResolver}
        set {_docimpl.conflictResolver = newValue}
    }


    /** Saves property changes back to the database.
        If the document in the database has been updated since it was read by this CBLDocument, a
        conflict occurs, which will be resolved by invoking the conflict handler. This can happen if
        multiple application threads are writing to the database, or a pull replication is copying
        changes from a server. */
    public func save() throws {
        try _docimpl.save()
    }


    /** Deletes this document. All properties are removed, and subsequent calls to -documentWithID:
        will return nil.
        Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
        change can be replicated to other databases. Thus, it does not free up all of the disk space
        occupied by the document.
        To delete a document entirely (but without the ability to replicate this), use -purge:. */
    public func delete() throws {
        try _docimpl.delete()
    }


    /** Purges this document from the database.
        This is more drastic than deletion: it removes all traces of the document.
        The purge will NOT be replicated to other databases. */
    public func purge() throws {
        try _docimpl.purge()
    }


    /** Reverts unsaved changes made to the document's properties. */
    public func revert() {
        _docimpl.revert()
    }

    /** Equal to operator for comparing two Documents object. */
    public static func == (doc1: Document, doc: Document) -> Bool {
        return doc._docimpl === doc._docimpl
    }

    // MARK: Internal
    
    init(_ impl: CBLDocument, inDatabase: Database) {
        database = inDatabase
        _docimpl = impl
        super.init(impl)
        
        _docimpl.swiftDocument = self
    }
    
    deinit {
        _docimpl.swiftDocument = nil
    }

    let _docimpl: CBLDocument
}
