//
//  CBLScope+Internal.h
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

#pragma once
#import "CBLScope.h"

@class CBLDatabase;

NS_ASSUME_NONNULL_BEGIN

@interface CBLScope ()

/** The database associated with the scope. When the (internal default) collection is cached in the database,
    the database of the collection's scope will be set to the weakdb to avoid circular retain references. */
@property (nonatomic, readonly, weak) CBLDatabase* weakdb;
@property (nonatomic, readonly, nullable) CBLDatabase* strongdb;

/** The cached mode indicates that the scope object will be cached (via the collection object) inside the database or not.
    When the collection is cached, the collection will not retain the database inside the collection object to avoid
    the circular refererences. */
- (instancetype) initWithDB: (CBLDatabase*)db name: (NSString*)name cached: (BOOL)cached;

@end

NS_ASSUME_NONNULL_END
