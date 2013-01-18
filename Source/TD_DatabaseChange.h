//
//  TD_DatabaseChange.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/13.
//
//

#import <Foundation/Foundation.h>
@class TD_Database, TD_Revision;


/** Identifies a change to a database, i.e. a newly added revision. */
@interface TD_DatabaseChange : NSObject <NSCopying>

- (id) initWithAddedRevision: (TD_Revision*)addedRevision
             winningRevision: (TD_Revision*)winningRevision;

/** The revision just added. */
@property (readonly) TD_Revision* addedRevision;

/** The revision that is now the default "winning" revision of the document. */
@property (readonly) TD_Revision* winningRevision;

/** True if the document might be in conflict. */
@property bool maybeConflict;

/** Remote database URL that this change was pulled from, if any. */
@property (strong) NSURL* source;

@end
