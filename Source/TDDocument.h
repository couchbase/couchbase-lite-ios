//
//  TDDocument.h
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
#import "TDCache.h"
@class TDServer, TDDocRevision, TDQueryRow;


/** A TouchDB document (as opposed to any specific revision of it.) */
@interface TDDocument : NSObject <TDCacheable>
{
    TDDatabase* _database;
    TDCache* _owningCache;
    NSString* _docID;
    TDDocRevision* _currentRevision;
}

- (id)initWithDatabase: (TDDatabase*)database
            documentID: (NSString*)docID;       //FIX: Make internal

@property (readonly) TDDatabase* database;

@property (readonly) NSString* documentID;

#pragma mark REVISIONS:

/** The ID of the current revision (if known; else nil). */
@property (readonly, copy) NSString* currentRevisionID;

/** The current/latest revision. This object is cached. */
@property (readonly) TDDocRevision* currentRevision;

/** The revision with the specified ID. */
- (TDDocRevision*) revisionWithID: (NSString*)revisionID;


#pragma mark PROPERTIES:

/** The contents of the current revision of the document.
    This is shorthand for self.currentRevision.properties.
    Any keys in the dictionary that begin with "_", such as "_id" and "_rev", contain CouchDB metadata. */
@property (readonly, copy) NSDictionary* properties;

/** The user-defined properties, without the ones reserved by CouchDB.
    This is based on -properties, with every key whose name starts with "_" removed. */
@property (readonly, copy) NSDictionary* userProperties;

/** Shorthand for [self.properties objectForKey: key]. */
- (id) propertyForKey: (NSString*)key;

- (TDDocRevision*) putProperties: (NSDictionary*)properties error: (NSError**)outError;


- (void) revisionAdded: (TDRevision*)rev source: (NSURL*)source;    //FIX: INTERNAL
- (void) loadCurrentRevisionFrom: (TDQueryRow*)row; //FIX: INTERNAL
- (TDDocRevision*) putProperties: (NSDictionary*)properties //FIX: INTERNAL
                       prevRevID: (NSString*)prevID
                           error: (NSError**)outError;
@end
