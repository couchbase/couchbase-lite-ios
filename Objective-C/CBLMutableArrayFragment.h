//
//  CBLMutableArrayFragment.h
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

#import "CBLArrayFragment.h"
@class CBLMutableFragment;

NS_ASSUME_NONNULL_BEGIN

/** CBLMutableArrayFragment protocol provides subscript access to CBLMutableFragment objects by index. */
@protocol CBLMutableArrayFragment <CBLArrayFragment>

/** 
 Subscript access to a CBLMutableFragment object by index.
 
 @param index The index.
 @return The CBLMutableFragment object.
 */
- (nullable CBLMutableFragment*) objectAtIndexedSubscript: (NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
