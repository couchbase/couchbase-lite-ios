//
//  CBLFullTextIndexConfiguration.h
//  CouchbaseLite
//
//  Copyright (c) 2025 Couchbase, Inc All rights reserved.
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
#import <CouchbaseLite/CBLIndexConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

/** 
 Configuration for creating full-text indexes.
 */
@interface CBLFullTextIndexConfiguration : CBLIndexConfiguration

/**
 A predicate expression defining conditions for indexing documents.
 Only documents satisfying the predicate are included, enabling partial indexes.
 */
@property (nonatomic, readonly, nullable) NSString* where;

/**
 Set the true value to ignore accents/diacritical marks. 
 */
@property (nonatomic, readonly) BOOL ignoreAccents;

/**
 The language code which is an ISO-639 language such as "en", "fr", etc.
 Setting the language code affects how word breaks and word stems are parsed.
 Without setting the value, the current locale's language will be used. Setting
 a nil or "" value to disable the language features.
 */
@property (nonatomic, readonly, nullable) NSString* language;

/**
 Initializes a full-text index by using an array of expression strings
 @param expressions The array of expression strings.
 @param ignoreAccents The flag to ignore accents/diacritical marks.
 @param language Optional language code which is an ISO-639 language such as "en", "fr", etc.
 @return The full-text index configuration object.
 */
- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions
                      ignoreAccents: (BOOL)ignoreAccents
                           language: (nullable NSString*)language;

/**
 Initializes a full-text index with an array of expression strings and an optional where clause for a partial index.
 @param where Optional where clause for partial indexing.
 @param expressions The array of expression strings.
 @param ignoreAccents The flag to ignore accents/diacritical marks.
 @param language Optional language code which is an ISO-639 language such as "en", "fr", etc.
 @return The full-text index configuration object.
 */
- (instancetype) initWithExpression: (NSArray<NSString*>*)expressions
                              where: (nullable NSString*)where
                      ignoreAccents: (BOOL)ignoreAccents
                           language: (nullable NSString*)language;

@end

NS_ASSUME_NONNULL_END
