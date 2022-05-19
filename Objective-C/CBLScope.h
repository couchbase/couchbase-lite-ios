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

@protocol CBLScope <NSObject>

#pragma mark Properties

/** Scope name. */
@property (readonly, nonatomic) NSString* name;

#pragma mark Collections

/** Get all collections in the scope. */
- (NSArray<CBLCollection*>*) getCollections;

/**
 Get a collection in the scope by name.
 If the collection doesn't exist, a nil value will be returned. */
- (CBLCollection*) getCollectionWithName: (NSString*)name;

@end

/**  The default scope name constant */
extern NSString* const kCBLDefaultScopeName;

@interface CBLScope : NSObject<CBLScope>

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
