//
//  CBLFullTextIndex.h
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
#import "CBLIndex.h"

NS_ASSUME_NONNULL_BEGIN

@interface CBLFullTextIndex: CBLIndex

/**
 Set the true value to ignore accents/diacritical marks. The default value is false.
 */
@property (nonatomic) BOOL ignoreAccents;

/**
 The language code which is an ISO-639 language such as "en", "fr", etc.
 Setting the language code affects how word breaks and word stems are parsed.
 Without setting the value, the current locale's language will be used. Setting
 a nil or "" value to disable the language features.
 */
@property (nonatomic, copy, nullable) NSString* language;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

/**
 Full-text Index Item.
 */
@interface CBLFullTextIndexItem: NSObject

/**
 Creates a full-text search index item with the given expression.
 
 @param property A property used to perform the match operation against with.
 @return The full-text search index item.
 */
+ (CBLFullTextIndexItem*) property: (NSString*)property;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
