//
//  CBLDocument.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 12/29/16.
//  Copyright © 2016 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLProperties.h"
@class CBLDatabase;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

/** Notification posted by a CBLDocument when a property is changed in memory. */
extern NSString* const kCBLDocumentChangeNotification;

/** Notification posted by a CBLDocument when it is updated in the database.
    This is posted after -save:, -deleteDocument:, or -purge: are called.
    It will also be posted if a change was made by another thread, and the local CBLDocument has
    reloaded its properties. In the latter case, the kCBLDocumentIsExternalUserInfoKey will have a
    value of YES. */
extern NSString* const kCBLDocumentSavedNotification;

/** Key in the userInfo dictionary of a kCBLDocumentSavedNotification.
    It will have a value of YES if the change was made by a different CBLDatabase or by the
    replicator. */
extern NSString* const kCBLDocumentIsExternalUserInfoKey;


/** A Couchbase Lite document.
    A document has key/value properties like an NSDictionary; their API is defined by the
    protocol CBLProperties. To learn how to work with properties, see that protocol's
    documentation. */
@interface CBLDocument : CBLProperties

- (instancetype) init NS_UNAVAILABLE;

/** The document's ID. */
@property (readonly, nonatomic) NSString* documentID;

/** The document's owning database. */
@property (readonly, nonatomic) CBLDatabase* database;

/** Is the document deleted? */
@property (readonly, nonatomic) BOOL isDeleted;

/** Checks whether the document exists in the database or not.
    If not, saving it will create it. */
@property (readonly, nonatomic) BOOL exists;

/** Sequence number of the document in the database.
    This indicates how recently the document has been changed: every time any document is updated,
    the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
    property changes that means it's been changed (on-disk); and if one document's `sequence`
    is greater than another's, that means it was changed more recently. */
@property (readonly, nonatomic) uint64_t sequence;

/** The conflict resolver, if any, specific to this document.
    If nil, the database's conflict resolver will be used. */
@property (nonatomic, nullable) id<CBLConflictResolver> conflictResolver;

/** Saves property changes back to the database.
    If the document in the database has been updated since it was read by this CBLDocument, a
    conflict occurs, which will be resolved by invoking the conflict handler. This can happen if
    multiple application threads are writing to the database, or a pull replication is copying
    changes from a server. */
- (BOOL) save: (NSError**)error;

/** Deletes this document. All properties are removed, and subsequent calls to -documentWithID:
    will return nil.
    Deletion adds a special "tombstone" revision to the database, as bookkeeping so that the
    change can be replicated to other databases. Thus, it does not free up all of the disk space
    occupied by the document.
    To delete a document entirely (but without the ability to replicate this), use -purge:. */
- (BOOL) deleteDocument: (NSError**)error;

/** Purges this document from the database.
    This is more drastic than deletion: it removes all traces of the document.
    The purge will NOT be replicated to other databases. */
- (BOOL) purge: (NSError**)error;


@end

/** Define Subscription methods for CBLDocument. */
@interface CBLDocument (Subscripts)

/** Same as objectForKey: */
- (nullable id) objectForKeyedSubscript: (NSString*)key;

/** Same as setObject:forKey: */
- (void) setObject: (nullable id)value forKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END

// TODO:
// 1. Modellable
