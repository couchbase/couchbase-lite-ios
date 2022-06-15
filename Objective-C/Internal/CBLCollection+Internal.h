//
//  CBLCollection+Internal.h
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
#import "CBLCollection.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLCollection ()

/** The database associated with the collection. */
@property (nonatomic, readonly) CBLDatabase* db;

/** This constructor will return CBLCollection for the c4collection. */
- (instancetype) initWithDB: (CBLDatabase*)db
               c4collection: (C4Collection*)c4collection
                      error: (NSError**)error;
@end

NS_ASSUME_NONNULL_END
