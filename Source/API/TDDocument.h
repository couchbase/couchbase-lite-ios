//
//  TDDocument.h
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDRevision, TDNewRevision;


/** A TouchDB document (as opposed to any specific revision of it.) */
@interface TDDocument : NSObject

/** The document's owning database. */
@property (readonly) TDDatabase* database;

/** The document's ID. */
@property (readonly) NSString* documentID;

/** An abbreviated form of the the documentID that looks like "xxxx..xxxx". Useful in logging. */
@property (readonly) NSString* abbreviatedID;

/** Is this document deleted? (That is, does its current revision have the '_deleted' property?) */
@property (readonly) BOOL isDeleted;

/** Deletes this document by adding a deletion revision.
    This will be replicated to other databases. */
- (BOOL) deleteDocument: (NSError**)outError;

/** Purges this document from the database; this is more than deletion, it forgets entirely about it.
    The purge will NOT be replicated to other databases. */
- (BOOL) purgeDocument: (NSError**)outError;


#pragma mark REVISIONS:

/** The ID of the current revision (if known; else nil). */
@property (readonly, copy) NSString* currentRevisionID;

/** The current/latest revision. This object is cached. */
@property (readonly) TDRevision* currentRevision;

/** The revision with the specified ID. */
- (TDRevision*) revisionWithID: (NSString*)revisionID;

/** Returns the document's history as an array of TDRevisions. (See TDRevision's method.) */
- (NSArray*) getRevisionHistory: (NSError**)outError;

/** Returns all the current conflicting revisions of the document. If the document is not
    in conflict, only the single current revision will be returned. */
- (NSArray*) getConflictingRevisions: (NSError**)outError;

/** Returns all the leaf revisions in the document's revision tree,
    including deleted revisions (i.e. previously-resolved conflicts.) */
- (NSArray*) getLeafRevisions: (NSError**)outError;

/** Creates an unsaved new revision whose parent is the currentRevision,
    or which will be the first revision if the document doesn't exist yet.
    You can modify this revision's properties and attachments, then save it.
    No change is made to the database until/unless you save the new revision. */
- (TDNewRevision*) newRevision;


#pragma mark PROPERTIES:

/** The contents of the current revision of the document.
    This is shorthand for self.currentRevision.properties.
    Any keys in the dictionary that begin with "_", such as "_id" and "_rev", contain TouchDB metadata. */
@property (readonly, copy) NSDictionary* properties;

/** The user-defined properties, without the ones reserved by CouchDB.
    This is based on -properties, with every key whose name starts with "_" removed. */
@property (readonly, copy) NSDictionary* userProperties;

/** Shorthand for [self.properties objectForKey: key]. */
- (id) propertyForKey: (NSString*)key;

/** Same as -propertyForKey:. Enables "[]" access in Xcode 4.4+ */
- (id)objectForKeyedSubscript:(NSString*)key;

/** Saves a new revision. The properties dictionary must have a "_rev" property whose ID matches the current revision's (as it will if it's a modified copy of this document's .properties property.) */
- (TDRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError;


#pragma mark MODEL:

/** Optional reference to an application-defined model object representing this document.
    Usually this is a TDModel, but you can implement your own model classes if you want.
    Note that this is a weak reference. */
@property (weak) id modelObject;


@end



/** Protocol that TDDocument model objects must implement. See the TDModel class. */
@protocol TDDocumentModel <NSObject>
/** If a TDDocument's modelObject implements this method, it will be called whenever the document posts a kTDDocumentChangeNotification. */
- (void) tdDocumentChanged: (TDDocument*)doc;
@end



/** This notification is posted by a TDDocument in response to an external change.
    It is not sent in response to 'local' changes made by this TDDatabase's object tree. */
extern NSString* const kTDDocumentChangeNotification;
