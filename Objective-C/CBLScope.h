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

NS_ASSUME_NONNULL_BEGIN

/**  The default scope name constant */
extern NSString* const kCBLDefaultScopeName;

/**
 A CBLScope represents a scope or namespace of the collections.
 
 The scope implicitly exists when there is at least one collection created under the scope.
 The default scope is exceptional in that it will always exists even there are no collections
 under it.
 
 `CBLScope` Lifespan
 `CBLScope` is ref-counted and is owned by the database object that creates it. Hence,
 most of the time there is no need to retain or release it. A `CBLScope` object and its
 reference remain valid until either the database is closed or the scope itself is invalidated
 as all collections in the scope have been deleted.
 If the scope reference needs to be kept longer, the scope object should be retained,
 and the reference will remain valid until it's released. Most operations on the invalid
 CBLScope object will fail with null or empty result.
 */
@interface CBLScope : NSObject

/** Scope name. */
@property (readonly, nonatomic) NSString* name;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

#pragma mark Collections

/** Get all collections in the scope. */
- (NSArray<CBLCollection*>*) collections;

/**
 Get a collection in the scope by name.
 If the collection doesn't exist, a nil value will be returned. */
- (CBLCollection*) collectionWithName: (NSString*)name;

@end

NS_ASSUME_NONNULL_END
