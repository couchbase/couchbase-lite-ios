//
//  ConflictTest.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 6/27/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

@interface TheirsWins : NSObject <CBLConflictResolver>
@end

@interface MergeThenTheirsWins : NSObject <CBLConflictResolver>
@end

@interface GiveUp : NSObject <CBLConflictResolver>
@end

@interface DoNotResolve : NSObject <CBLConflictResolver>
@end
