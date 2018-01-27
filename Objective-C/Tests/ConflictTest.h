//
//  ConflictTest.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/27/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

NS_ASSUME_NONNULL_BEGIN

@interface TestResolver : NSObject <CBLConflictResolver>
@property (atomic) BOOL requireBaseRevision;
@property (readonly, atomic) BOOL wasCalled;
@end

/** Default Conflict Resolution set to ConflictTest which 
    will just make the assertion false as shouldn't be called. */
@interface DoNotResolve : TestResolver
@end

/** Select my version. */
@interface MineWins : TestResolver
@end

/** Select their version. */
@interface TheirsWins : TestResolver
@end

/** Merge, but if both sides changed the same property then use their value. */
@interface MergeThenTheirsWins : TestResolver
@end

/** Return nil to give up the conflict resolving. The document save operation will return 
    the conflicting error. */
@interface GiveUp : TestResolver
@end

/** Block based resolver */
@interface BlockResolver : TestResolver

@property (atomic, readonly) CBLDocument* (^block)(CBLConflict*);

- (instancetype) initWithBlock: (nullable CBLDocument* (^)(CBLConflict*))block;

@end

NS_ASSUME_NONNULL_END
