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

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCBLDocumentChangeNotification;
extern NSString* const kCBLDocumentSavedNotification;
extern NSString* const kCBLDocumentIsExternalUserInfoKey;

/** A CouchbaseLite document. */
@interface CBLDocument : CBLProperties

- (instancetype) init NS_UNAVAILABLE;

/** The document's ID. */
@property (readonly, nonatomic) NSString* documentID;

/** The document's owning database. */
@property (readonly, nonatomic) CBLDatabase* database;

/** Is the document deleted? */
@property (readonly) BOOL isDeleted;

/** Check whether the document exists? in the database or not. */
- (BOOL) exists;

/** Sequence number of the document in the database. */
@property (readonly) uint64_t sequence;

/** Save the document. */
- (BOOL) save: (NSError**)outError;

/** Deletes this document by adding a deletion revision. 
 This will be replicated to other databases. */
- (BOOL) deleteDocument: (NSError**)outError;

/** Purges this document from the database; this is more than deletion, it forgets entirely about it.
 The purge will NOT be replicated to other databases. */
- (BOOL) purge: (NSError**)outError;

/** Revert changes made to the document. */
- (void) revert;

@end

NS_ASSUME_NONNULL_END

// TODO:
// 1. Modellable
// 2. Save/Delete with Conflict Resolver
// 3. Change Listener
