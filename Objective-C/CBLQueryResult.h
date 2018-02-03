//
//  CBLQueryResult.h
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
#import "CBLArray.h"
#import "CBLDictionary.h"

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryResult represents a single row in the query result. The projecting result value
 can be accessed either by using a zero based index or by a key corresponding to the
 CBLQuerySelectResult objects given when constructing the CBLQuery object.
 
 A key used for accessing the projecting result value could be one of the followings:
 * The alias name of the CBLQuerySelectResult object.
 * The last component of the keypath or property name of the property expression used
 when creating the CBLQuerySelectResult object.
 * The provision key in $1, $2, ...$N format for the CBLQuerySelectResult that doesn't have
 an alias name specified or is not a property expression such as an aggregate function
 expression (e.g. count(), avg(), min(), max(), sum() and etc). The number suffix
 after the '$' character is a running number starting from one.
 */
@interface CBLQueryResult : NSObject <CBLArray, CBLDictionary>

/** Not Available. */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
