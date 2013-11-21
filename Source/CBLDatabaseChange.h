//
//  CBLDatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import <Foundation/Foundation.h>


/** Identifies a change to a database, that is, a newly added document revision.
    The CBLDocumentChangeNotification contains one of these in the "changes" key of its
    userInfo dictionary, and CBLDatabaseChangeNotification contains an array.  */
@interface CBLDatabaseChange : NSObject <NSCopying>

/** The ID of the document that changed. */
@property (readonly) NSString* documentID;

/** The ID of the newly-added revision. */
@property (readonly) NSString* revisionID;

/** YES if the new revision is the current (default, winning) one. */
@property (readonly) BOOL isCurrentRevision;

/** YES if the document might be in conflict. */
@property (readonly) BOOL maybeConflict;

/** The remote database URL that this change was pulled from, if any. */
@property (readonly) NSURL* source;

@end
