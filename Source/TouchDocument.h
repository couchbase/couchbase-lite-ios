//
//  TDDocument.h
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TouchDatabase.h"
#import "TDCache.h"
@class TouchRevision, TouchQueryRow;


/** A TouchDB document (as opposed to any specific revision of it.) */
@interface TouchDocument : NSObject <TDCacheable>
{
    @private
    TouchDatabase* _database;
    TDCache* _owningCache;
    NSString* _docID;
    TouchRevision* _currentRevision;
    id _modelObject;
}

@property (readonly) TouchDatabase* database;

@property (readonly) NSString* documentID;

#pragma mark REVISIONS:

/** The ID of the current revision (if known; else nil). */
@property (readonly, copy) NSString* currentRevisionID;

/** The current/latest revision. This object is cached. */
@property (readonly) TouchRevision* currentRevision;

/** The revision with the specified ID. */
- (TouchRevision*) revisionWithID: (NSString*)revisionID;


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

/** Saves a new revision. The properties dictionary must have a "_rev" property whose ID matches the current revision's (as it will if it's a modified copy of this document's .properties property.) */
- (TouchRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError;

#pragma mark MODEL:

/** Optional reference to an application-defined model object representing this document.
 This property is unused and uninterpreted by TouchDB; use it for whatever you want.
 Note that this is not a strong/retained reference. */
@property (assign) id modelObject;


@end



@protocol TouchDocumentModel <NSObject>
/** If a TouchDocument's modelObject implements this method, it will be called whenever the document posts a kTouchDocumentChangeNotification. */
- (void) touchDocumentChanged: (TouchDocument*)doc;
@end



/** This notification is posted by a TouchDocument in response to an external change.
    It is not sent in response to 'local' changes made by this TouchDatabase's object tree. */
extern NSString* const kTouchDocumentChangeNotification;
