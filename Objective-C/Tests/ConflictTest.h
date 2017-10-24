//
//  ConflictTest.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/27/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

NS_ASSUME_NONNULL_BEGIN

/** Default Conflict Resolution set to ConflictTest which 
    will just make the assertion false as shouldn't be called. */
@interface DoNotResolve : NSObject <CBLConflictResolver>
@end

/** Select theirs version. */
@interface TheirsWins : NSObject <CBLConflictResolver>
@end


/** Merge or select theirs version. */
@interface MergeThenTheirsWins : NSObject <CBLConflictResolver>
@property (atomic) BOOL requireBaseRevision;
@end

/** Return nil to give up the conflict resolving. The document save operation will return 
    the conflicting error. */
@interface GiveUp : NSObject <CBLConflictResolver>
@end

/** Block based resolver */
@interface BlockResolver : NSObject <CBLConflictResolver>

@property (atomic, readonly) CBLDocument* (^block)(CBLConflict*);

- (instancetype) initWithBlock: (nullable CBLDocument* (^)(CBLConflict*))block;

@end

NS_ASSUME_NONNULL_END
