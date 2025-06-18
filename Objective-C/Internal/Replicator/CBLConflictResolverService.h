//
//  CBLReplicationConflictResolver.h
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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

#import <Foundation/Foundation.h>

@class CBLCollection;
@class CBLReplicatedDocument;
@protocol CBLConflictResolver;

NS_ASSUME_NONNULL_BEGIN

@interface CBLConflictResolverService : NSObject

- (instancetype) initWithReplicatorID: (NSString*)replicatorID;

- (BOOL) shutdownAndWait: (BOOL)waitForPendingTasks completion:(void (^)(void))completion;

- (void) addConflict: (CBLReplicatedDocument*)doc
          collection: (CBLCollection*)collection
            resolver: (nullable id<CBLConflictResolver>)resolver
          completion: (void (^)(BOOL cancelled, NSError* _Nullable error))completion;

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
