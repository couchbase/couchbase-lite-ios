//
//  CBLDictionaryFragment.h
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

@class CBLFragment;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLDictionaryFragment protocol provides subscript access to CBLFragment
 objects by key.
 */
@protocol CBLDictionaryFragment <NSObject>

/** 
 Subscript access to a CBLFragment object by key.
 
 @param key The key.
 @return The CBLFragment object.
 */
- (nullable CBLFragment*) objectForKeyedSubscript: (NSString*)key;

@end

NS_ASSUME_NONNULL_END
