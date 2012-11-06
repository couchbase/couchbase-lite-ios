//
//  TouchRevision.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TouchDocument, TDRevision, TouchDatabase, TouchAttachment;


/** A revision of a document. */
@interface TouchRevision : NSObject
{
    @private
    TouchDocument* _document;
    TDRevision* _rev;
    BOOL _checkedProperties;
}

/** The document this is a revision of. */
@property (readonly) TouchDocument* document;

@property (readonly) TouchDatabase* database;

/** The ID of this revision. */
@property (readonly) NSString* revisionID;

/** Does this revision mark the deletion of its document? */
@property (readonly) BOOL isDeleted;


#pragma mark PROPERTIES

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

/** Has this object fetched its contents from the database yet? */
@property (readonly) BOOL propertiesAreLoaded;

/** Saves a new revision with the given properties.
    This will fail with a 412 error if the receiver is not the current revision of the document. */
- (TouchRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError;

/** Deletes the document by creating a new deletion-marker revision. */
- (TouchRevision*) deleteDocument: (NSError**)outError;

#pragma mark - HISTORY:

- (NSArray*) getRevisionHistory: (NSError**)outError;

#pragma mark ATTACHMENTS

/** The names of all attachments (array of strings). */
@property (readonly) NSArray* attachmentNames;

/** Looks up the attachment with the given name (without fetching its contents yet). */
- (TouchAttachment*) attachmentNamed: (NSString*)name;

/** All attachments, as TouchAttachment objects. */
@property (readonly) NSArray* attachments;

@end
