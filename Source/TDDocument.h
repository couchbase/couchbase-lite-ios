//
//  TDDocument.h
//  TouchDB
//
//  Created by Jens Alfke on 6/4/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "TDDatabase.h"
@class TDServer;


@interface TDDocument : NSObject
{
    TDServer* _server;  // weak
    NSString* _databaseName;
    NSString* _docID;
    UInt64 _numericID;
    TDRevision* _currentRevision;
    TDContentOptions _currentRevisionOptions;
    BOOL _deleted;
}

@property (readonly) TDDatabase* database;

@property (readonly) NSString* documentID;

@property (readonly) TDRevision* currentRevision;

- (TDRevision*) revisionWithID: (NSString*)revID
                       options: (TDContentOptions)options;

/** YES if the document has been deleted from the database. */
@property (readonly) BOOL isDeleted;


#pragma mark REVISIONS:

/** The ID of the current revision (if known; else nil). */
@property (readonly, copy) NSString* currentRevisionID;

/** The current/latest revision. This object is cached. */
- (TDRevision*) currentRevision;

/** The revision with the specified ID. */
- (TDRevision*) revisionWithID: (NSString*)revisionID;

- (TDRevision*) revisionWithID: (NSString*)revID options: (TDContentOptions)options;

/** Returns an array of available revisions.
    The ordering is essentially arbitrary, but usually chronological (unless there has been merging with changes from another server.)
    The number of historical revisions available may vary; it depends on how recently the database has been compacted. You should not rely on earlier revisions being available, except for those representing unresolved conflicts. */
- (NSArray*) getRevisionHistory;


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

/** Updates the document with new properties, creating a new revision (Asynchronous.)
    The properties dictionary needs to contain a "_rev" key whose value is the current revision's ID; the dictionary returned by -properties will already have this, so if you modify that dictionary you're OK. The exception is if this is a new document, as there is no current revision, so no "_rev" key is needed.
    If the PUT succeeds, the operation's resultObject will be set to the new CouchRevision.
    You should be prepared for the operation to fail with a 412 status, indicating that a newer revision has already been added by another client.
    In this case you need to call -currentRevision again, to get that newer revision, incorporate any changes into your properties dictionary, and try again. (This is not the same as a conflict resulting from synchronization. Those conflicts result in multiple versions of a document appearing in the database; but in this case, you were prevented from creating a conflict.) */
- (TDStatus) putProperties: (NSDictionary*)properties;


@end
