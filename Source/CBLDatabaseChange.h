//
//  CBLDatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import "CBLBase.h"

NS_ASSUME_NONNULL_BEGIN

/** Identifies a change to a database, that is, a newly added document revision.
    The CBLDocumentChangeNotification contains one of these in the "change" key of its
    userInfo dictionary, and CBLDatabaseChangeNotification contains an NSArray in "changes".  */
@interface CBLDatabaseChange : NSObject <NSCopying>

/** The ID of the document that changed. */
@property (readonly) NSString* documentID;

/** The ID of the newly-added revision. A nil value means the document was purged. */
@property (readonly, nullable) NSString* revisionID;

/** Is the new revision the document's current (default, winning) one?
    If not, there's a conflict. */
@property (readonly) BOOL isCurrentRevision;

/** YES if the document is in conflict. (The conflict might pre-date this change.) */
@property (readonly) BOOL inConflict;

/** YES of the document is deleted. */
@property (readonly) BOOL isDeletion;

/** The remote database URL that this change was pulled from, if any. */
@property (readonly, nullable) NSURL* source;

- (instancetype) init NS_UNAVAILABLE;

@end


NS_ASSUME_NONNULL_END
