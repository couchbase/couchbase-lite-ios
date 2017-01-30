//
//  CBLConflictResolver.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/** Abstract interface for an application-defined object that can resolve a conflict between two
    revisions of a document. Called when saving a CBLDocument, when there is a a newer revision
    already in the database; and also when the replicator pulls a remote revision that conflicts
    with a locally-saved revision. */
@protocol CBLConflictResolver <NSObject>

/** Resolves conflicting edits of a document against their common base.
    @param localProperties  The revision that is being saved, or the revision in the local
                database for which there is a server-side conflict.
    @param conflictingProperties  The conflicting revision that is already stored in the
                database, or on the server.
    @param baseProperties  The common parent revision of these two revisions, if available.
    @return  The resolved set of properties for the document to store, or nil to give up if
                automatic resolution isn't possible. */
- (nullable NSDictionary*) resolveMine: (NSDictionary*)localProperties
                            withTheirs: (NSDictionary*)conflictingProperties
                               andBase: (NSDictionary*)baseProperties;

@end


NS_ASSUME_NONNULL_END
