//
//  CBLDocument.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
@class CBLRevision, CBLNewRevision;


/** A CouchbaseLite document (as opposed to any specific revision of it.) */
@interface CBLDocument : NSObject

/** The document's owning database. */
@property (readonly) CBLDatabase* database;

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
@property (readonly) CBLRevision* currentRevision;

/** The revision with the specified ID. */
- (CBLRevision*) revisionWithID: (NSString*)revisionID;

/** Returns the document's history as an array of CBLRevisions. (See CBLRevision's method.) */
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
- (CBLNewRevision*) newRevision;


#pragma mark PROPERTIES:

/** The contents of the current revision of the document.
    This is shorthand for self.currentRevision.properties.
    Any keys in the dictionary that begin with "_", such as "_id" and "_rev", contain CouchbaseLite metadata. */
@property (readonly, copy) NSDictionary* properties;

/** The user-defined properties, without the ones reserved by CouchDB.
    This is based on -properties, with every key whose name starts with "_" removed. */
@property (readonly, copy) NSDictionary* userProperties;

/** Shorthand for [self.properties objectForKey: key]. */
- (id) propertyForKey: (NSString*)key                                   __attribute__((nonnull));

/** Same as -propertyForKey:. Enables "[]" access in Xcode 4.4+ */
- (id)objectForKeyedSubscript:(NSString*)key                            __attribute__((nonnull));

/** Saves a new revision. The properties dictionary must have a "_rev" property whose ID matches the current revision's (as it will if it's a modified copy of this document's .properties property.) */
- (CBLRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError;

/** Saves a new revision by letting the caller update the existing properties.
    This method handles conflicts by retrying (calling the block again).
    The block body should modify the properties of the new revision and return YES to save or
    NO to cancel. Be careful: the block can be called multiple times if there is a conflict!
    @param block  Will be called on each attempt to save. Should update the given revision's
            properties and then return YES, or just return NO to cancel.
    @param outError  Will point to the error, if the method returns nil. (If the callback block
            cancels by returning nil, the error will be nil.) If this parameter is NULL, no
            error will be stored.
    @return  The new saved revision, or nil on error or cancellation.
 */
- (CBLRevision*) update: (BOOL(^)(CBLNewRevision*))block
                  error: (NSError**)outError                            __attribute__((nonnull(1)));


#pragma mark MODEL:

/** Optional reference to an application-defined model object representing this document.
    Usually this is a CBLModel, but you can implement your own model classes if you want.
    Note that this is a weak reference. */
@property (weak) id modelObject;


@end



/** Protocol that CBLDocument model objects must implement. See the CBLModel class. */
@protocol CBLDocumentModel <NSObject>
/** If a CBLDocument's modelObject implements this method, it will be called whenever the document posts a kCBLDocumentChangeNotification. */
- (void) tdDocumentChanged: (CBLDocument*)doc                           __attribute__((nonnull));
@end



/** This notification is posted by a CBLDocument in response to an external change.
    It is not sent in response to 'local' changes made by this CBLDatabase's object tree. */
extern NSString* const kCBLDocumentChangeNotification;
