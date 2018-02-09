//
//  CBLConflictResolver.h
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
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/**  
 CBLConflict provides details about a conflict. 
 */
@interface CBLConflict : NSObject

/** Mine version of the document. */
@property (nonatomic, readonly) CBLDocument* mine;

/** Theirs version of the document. */
@property (nonatomic, readonly) CBLDocument* theirs;

/** Base or common anchester version of the document. */
@property (nonatomic, readonly, nullable) CBLDocument* base;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end


/** 
 A protocol for an application-defined object that can resolve a conflict between two versions 
 of a document along with the base or the common ancester document if available. Called when saving 
 a CBLMutableDocument, when there is a a newer revision already in the database; and also when the 
 replicator pulls a remote revision that conflicts with a locally-saved revision. 
 */
@protocol CBLConflictResolver <NSObject>

/**
 Resolves the given conflict. Returning a nil document means giving up the conflict resolution
 and will result to a conflicting error returned when saving the document.
 
 @param conflict The conflict object.
 @return The result document of the conflict resolution.
 */
- (nullable CBLDocument*) resolve: (CBLConflict*)conflict;

@end


NS_ASSUME_NONNULL_END
