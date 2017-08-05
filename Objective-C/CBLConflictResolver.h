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

/**  
 CBLConflict provides details about a conflict. 
 */
@interface CBLConflict : NSObject

/** Mine version of the document. */
@property (nonatomic, readonly) CBLReadOnlyDocument* mine;

/** Theirs version of the document. */
@property (nonatomic, readonly) CBLReadOnlyDocument* theirs;

/** Base or common anchester version of the document. */
@property (nonatomic, readonly, nullable) CBLReadOnlyDocument* base;

@end


/** 
 A protocol for an application-defined object that can resolve a conflict between two versions 
 of a document along with the base or the common ancester document if available. Called when saving 
 a CBLDocument, when there is a a newer revision already in the database; and also when the 
 replicator pulls a remote revision that conflicts with a locally-saved revision. 
 */
@protocol CBLConflictResolver <NSObject>

/**
 Resolves the given conflict. Returning a nil document means giving up the conflict resolution
 and will result to a conflicting error returned when saving the document.
 
 @param conflict The conflict object.
 @return The result document of the conflict resolution.
 */
- (nullable CBLReadOnlyDocument*) resolve: (CBLConflict*)conflict;

@end


NS_ASSUME_NONNULL_END
