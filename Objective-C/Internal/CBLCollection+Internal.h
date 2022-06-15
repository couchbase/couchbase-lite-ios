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

/** internal c4collection instance */
@property (nonatomic, readonly) C4Collection* c4col;

/** weak db reference */
@property (nonatomic, readonly, weak) CBLDatabase* db;

/**
 This constructor will return the collection for the specified details
 */
- (instancetype) initWithDB: (CBLDatabase*)db
             collectionName: (NSString*)collectionName
                  scopeName: (nullable NSString*)scopeName
                      error: (NSError**)error;
@end

NS_ASSUME_NONNULL_END
