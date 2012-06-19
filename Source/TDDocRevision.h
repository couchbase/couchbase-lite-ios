//
//  TDDocRevision.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TDDocument, TDRevision, TDDatabase;


/** Public API for a revision of a document; not to be confused with the internal TDRevision. */
@interface TDDocRevision : NSObject
{
    TDDocument* _document;
    TDRevision* _rev;
}

- (id)initWithDocument: (TDDocument*)doc revision: (TDRevision*)rev;    //TODO: INTERNAL

/** The document this is a revision of. */
@property (readonly) TDDocument* document;

@property (readonly) TDDatabase* database;

/** The ID of this revision. */
@property (readonly) NSString* revisionID;

/** Does this revision mark the deletion of its document? */
@property (readonly) BOOL isDeleted;


#pragma mark PROPERTIES

/** The document as returned from the server and parsed from JSON. (Synchronous)
    Keys beginning with "_" are defined and reserved by CouchDB; others are app-specific.
    The properties are cached for the lifespan of this object, so subsequent calls after the first are cheap.
    (This accessor is synchronous.) */
@property (readonly, copy) NSDictionary* properties;

/** The user-defined properties, without the ones reserved by CouchDB.
    This is based on -properties, with every key whose name starts with "_" removed. */
@property (readonly, copy) NSDictionary* userProperties;

/** Shorthand for [self.properties objectForKey: key]. (Synchronous) */
- (id) propertyForKey: (NSString*)key;

/** Has this object fetched its contents from the server yet? */
@property (readonly) BOOL propertiesAreLoaded;

/** Creates a new revision with the given properties. */
- (TDDocRevision*) putProperties: (NSDictionary*)properties
                           error: (NSError**)outError;

/** Creates a new deletion-marker revision. */
- (TDDocRevision*) deleteDocument: (NSError**)outError;


@property (readonly) TDRevision* rev;   //TODO: INTERNAL
@end
