//
//  CBLReplicatorChange.h
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

#import <Foundation/Foundation.h>
@class CBLReplicator;
@class CBLReplicatorStatus;

/** Replicator status change details. */
@interface CBLReplicatorChange : NSObject

/** The replicator. */
@property (nonatomic, readonly) CBLReplicator* replicator;

/** The changed status. */
@property (nonatomic, readonly) CBLReplicatorStatus* status;

/** Scope Name.  */
@property (nonatomic, readonly) NSString* scope;

/** Collection Name. */
@property (nonatomic, readonly) NSString* collection;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end
