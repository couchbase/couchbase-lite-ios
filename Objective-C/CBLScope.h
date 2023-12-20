//
//  CBLScope.h
//  CouchbaseLite
//
//  Copyright (c) 2022 Couchbase, Inc All rights reserved.
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
@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

/**  The default scope name constant */
extern NSString* const kCBLDefaultScopeName;

/**
 A CBLScope represents a scope or namespace of the collections.
 
 The scope implicitly exists when there is at least one collection created under the scope.
 The default scope is exceptional in that it will always exists even there are no collections
 under it.
 
 `CBLScope` Lifespan
 A `CBLScope` object remain valid until either the database is closed or
 the scope itself is invalidated as all collections in the scope have been deleted.
 */
@interface CBLScope : NSObject

/** Scope name. */
@property (readonly, nonatomic) NSString* name;

/** Scope name. */
@property (readonly, nonatomic) CBLDatabase* database;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

#pragma mark Collections

/**
 Get all collections in the scope.
 
 @param error On return, the error if any.
 @return Collections in the scope, or nil if an error occurred.
 */
- (nullable NSArray<CBLCollection*>*) collections: (NSError**)error;

/**
 Get a collection in the scope by name.
 If the collection doesn't exist, a nil value will be returned.
 
 @param error On return, the error if any.
 @return Collection for the specified name, or nil if an error occurred.
 */
- (nullable CBLCollection*) collectionWithName: (NSString*)name error: (NSError**)error NS_SWIFT_NOTHROW;

@end

NS_ASSUME_NONNULL_END
