//
//  TDRevision.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDocument, TDDatabase, TDAttachment, TDNewRevision;


/** A revision of a TDDocument.
    Common base class of TDRevision (existing revisions) and TDNewRevision (revisions yet to be saved). */
@interface TDRevisionBase : NSObject

/** The document this is a revision of. */
@property (readonly) TDDocument* document;

@property (readonly) TDDatabase* database;

/** Does this revision mark the deletion of its document? */
@property (readonly) BOOL isDeleted;

/** The ID of this revision. Will be nil if this is a TDNewRevision. */
@property (readonly) NSString* revisionID;

/** The revision's contents as parsed from JSON.
    Keys beginning with "_" are defined and reserved by TouchDB; others are app-specific.
    The properties are cached for the lifespan of this object, so subsequent calls after the first are cheap. */
@property (readonly, copy) NSDictionary* properties;

/** The user-defined properties, without the ones reserved by TouchDB.
    This is based on -properties, with every key whose name starts with "_" removed. */
@property (readonly, copy) NSDictionary* userProperties;

/** Shorthand for [self.properties objectForKey: key]. */
- (id) propertyForKey: (NSString*)key;

/** Same as -propertyForKey:. Enables "[]" access in Xcode 4.4+ */
- (id) objectForKeyedSubscript: (NSString*)key;

#pragma mark ATTACHMENTS

/** The names of all attachments (array of strings). */
@property (readonly) NSArray* attachmentNames;

/** Looks up the attachment with the given name (without fetching its contents yet). */
- (TDAttachment*) attachmentNamed: (NSString*)name;

/** All attachments, as TDAttachment objects. */
@property (readonly) NSArray* attachments;

@end



/** An existing revision of a TDDocument. */
@interface TDRevision : TDRevisionBase

/** Has this object fetched its contents from the database yet? */
@property (readonly) BOOL propertiesAreLoaded;

/** Creates a new mutable revision whose properties and attachments you can modify and then save. */
- (TDNewRevision*) newRevision;

/** Saves a new revision with the given properties.
    This will fail with a 412 error if the receiver is not the current revision of the document. */
- (TDRevision*) putProperties: (NSDictionary*)properties
                        error: (NSError**)outError;

/** Deletes the document by creating a new deletion-marker revision. */
- (TDRevision*) deleteDocument: (NSError**)outError;

- (NSArray*) getRevisionHistory: (NSError**)outError;

@end



/** An unsaved new revision. */
@interface TDNewRevision : TDRevisionBase

@property (readwrite) BOOL isDeleted;
@property (readwrite, copy) NSMutableDictionary* properties;
@property (readonly, copy) NSDictionary* userProperties;

@property (readonly) TDRevision* parentRevision;
@property (readonly) NSString* parentRevisionID;

/** Property setter, enables [] assignment */
- (void) setObject: (id)object forKeyedSubscript: (NSString*)key;

/** Saves the new revision to the database.
    This will fail with a 412 error if its parent (the revision it was created from) is not the current revision of the document.
    Afterwards you should use the returned TDRevision instead of this object.
    @return  A new TDRevision representing the saved form of the revision. */
- (TDRevision*) save: (NSError**)outError;

/** Creates or updates an attachment.
    The attachment data will be written to the database when the revision is saved.
    @param attachment  A newly-created TDAttachment (not yet associated with any revision)
    @param name  The attachment name. */
- (void) addAttachment: (TDAttachment*)attachment named: (NSString*)name;

/** Deletes any existing attachment with the given name.
    The attachment will be deleted from the database when the revision is saved. */
- (void) removeAttachmentNamed: (NSString*)name;

@end