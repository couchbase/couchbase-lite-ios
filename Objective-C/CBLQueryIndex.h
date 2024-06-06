//
//  CBLQueryIndex.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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
#import <CouchbaseLite/CBLCollection.h>
#import <CouchbaseLite/CBLIndexUpdater.h>

NS_ASSUME_NONNULL_BEGIN
/**
 QueryIndex object represents an existing index in the collection.
 */

@interface CBLQueryIndex : NSObject

@property (readonly, nonatomic) CBLCollection* collection;

@property (readonly, nonatomic) NSString* name;

/**
 ENTERPRISE EDITION ONLY

 For updating lazy vector indexes only.
 Finds new or updated documents for which vectors need to be (re)computed and
 return an IndexUpdater object used for setting the computed vectors for updating the index.
 The limit parameter is for setting the max number of vectors to be computed.
 
 If index is up-to-date, null will be returned.

 If the index is not lazy, a CouchbaseLiteException will be thrown.
 */

- (nullable CBLIndexUpdater*) beginUpdate:(uint64_t) limit
                                 error:(NSError**) error;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
