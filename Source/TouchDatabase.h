//
//  TouchDatabase.h
//  TouchDB
//
//  Created by Jens Alfke on 6/17/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TDDatabase+Insertion.h"
#import "TDView.h"
@class TouchDatabaseManager, TouchDocument, TouchView, TouchQuery, TouchReplication, TouchModelFactory;
@class TDDatabase, TDCache;


/** A TouchDB database. */
@interface TouchDatabase : NSObject
{
    @private
    TouchDatabaseManager* _manager;
    TDDatabase* _tddb;    
    TDCache* _docCache;
    TouchModelFactory* _modelFactory;   // used in category method in TouchModelFactory.m
}

/** The database's name. */
@property (readonly) NSString* name;

/** The database manager that owns this database. */
@property (readonly) TouchDatabaseManager* manager;

- (BOOL) deleteDatabase: (NSError**)outError;

@property (readonly) NSUInteger documentCount;
@property (readonly) SequenceNumber lastSequenceNumber;

/** Instantiates a TDDocument object with the given ID.
    Doesn't touch the on-disk database; a document with that ID doesn't even need to exist yet.
    TDDocuments are cached, so there will never be more than one instance (in this database)
    at a time with the same documentID. */
- (TouchDocument*) documentWithID: (NSString*)docID;

/** Same as -documentWithID:. Enables "[]" access in Xcode 4.4+ */
- (TouchDocument*)objectForKeyedSubscript: (NSString*)key;

/** Creates a TDDocument object with no current ID.
    The first time you PUT to that document, it will be created on the server (via a POST). */
- (TouchDocument*) untitledDocument;

/** Returns the already-instantiated cached TouchDocument with the given ID, or nil if none is yet cached. */
- (TouchDocument*) cachedDocumentWithID: (NSString*)docID;

/** Empties the cache of recently used TDDocument objects.
    API calls will now instantiate and return new instances. */
- (void) clearDocumentCache;


/** Returns a query that matches all documents in the database. */
- (TouchQuery*) queryAllDocuments;

- (TouchQuery*) slowQueryWithMap: (TDMapBlock)mapBlock;

/** Returns a TouchView object for the view with the given name.
    (This succeeds even if the view doesn't already exist, but the view won't be added to the database until the TouchView is assigned a map function.) */
- (TouchView*) viewNamed: (NSString*)name;

/** An array of all existing views. */
@property (readonly) NSArray* allViews;


/** Define or clear a named document validation function.  */
- (void) defineValidation: (NSString*)validationName asBlock: (TDValidationBlock)validationBlock;
- (TDValidationBlock) validationNamed: (NSString*)validationName;


/** Define or clear a named filter function.  */
- (void) defineFilter: (NSString*)filterName asBlock: (TDFilterBlock)filterBlock;
- (TDFilterBlock) filterNamed: (NSString*)filterName;


/** Runs the block within a transaction. If the block returns NO, the transaction is rolled back.
    Use this when performing bulk operations like multiple inserts/updates; it saves the overhead of multiple SQLite commits. */
- (BOOL) inTransaction: (BOOL(^)(void))block;


- (TouchReplication*) pushToURL: (NSURL*)url;
- (TouchReplication*) pullFromURL: (NSURL*)url;
- (NSArray*) replicateWithURL: (NSURL*)otherDbURL exclusively: (bool)exclusively;


@end


/** This notification is posted by a TouchDatabase in response to document changes.
    Only one notification is posted per runloop cycle, no matter how many documents changed.
    If a change was not made by a TouchDocument belonging to this TouchDatabase (i.e. it came
    from another process or from a "pull" replication), the notification's userInfo dictionary will
    contain an "external" key with a value of YES. */
extern NSString* const kTouchDatabaseChangeNotification;
