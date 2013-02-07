//
//  CBL_DatabaseChange.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/13.
//
//

#import <Foundation/Foundation.h>
@class CBLDatabase, CBL_Revision;


/** Identifies a change to a database, i.e. a newly added revision. */
@interface CBL_DatabaseChange : NSObject <NSCopying>

- (instancetype) initWithAddedRevision: (CBL_Revision*)addedRevision
                       winningRevision: (CBL_Revision*)winningRevision;

/** The revision just added. */
@property (readonly) CBL_Revision* addedRevision;

/** The revision that is now the default "winning" revision of the document. */
@property (readonly) CBL_Revision* winningRevision;

/** True if the document might be in conflict. */
@property bool maybeConflict;

/** Remote database URL that this change was pulled from, if any. */
@property (strong) NSURL* source;

@end
