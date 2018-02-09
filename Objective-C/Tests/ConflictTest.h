//
//  ConflictTest.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
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
