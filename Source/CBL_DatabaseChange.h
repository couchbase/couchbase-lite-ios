//
//  CBL_DatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//  Copyright (c) 2013 Couchbase, Inc. All rights reserved.
//
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBL_Revision;


/** Identifies a change to a database, i.e. a newly added revision. */
@interface CBL_DatabaseChange : NSObject <NSCopying>

- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                       winningRevision: (CBL_Revision*)winningRevision;

/** The revision just added. Guaranteed immutable. */
@property (nonatomic, readonly) CBL_Revision* addedRevision;

/** The revision that is now the default "winning" revision of the document.
    Guaranteed immutable.*/
@property (nonatomic, readonly) CBL_Revision* winningRevision;

/** True if the document might be in conflict. */
@property (nonatomic) bool maybeConflict;

/** Remote database URL that this change was pulled from, if any. */
@property (nonatomic, strong) NSURL* source;

/** Is this a relayed notification of one from another thread, not the original? */
@property (nonatomic, readonly) bool echoed;

@end
