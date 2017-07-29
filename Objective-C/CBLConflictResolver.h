//
//  CBLConflictResolver.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/25/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBLReadOnlyDocument;

NS_ASSUME_NONNULL_BEGIN

@interface CBLConflict : NSObject

@property (atomic, readonly) CBLReadOnlyDocument* mine;

@property (atomic, readonly) CBLReadOnlyDocument* theirs;

@property (atomic, readonly, nullable) CBLReadOnlyDocument* base;

@end

/** Abstract interface for an application-defined object that can resolve a conflict between two
    revisions of a document. Called when saving a CBLDocument, when there is a a newer revision
    already in the database; and also when the replicator pulls a remote revision that conflicts
    with a locally-saved revision. */
@protocol CBLConflictResolver <NSObject>

- (nullable CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict;

@end


NS_ASSUME_NONNULL_END
