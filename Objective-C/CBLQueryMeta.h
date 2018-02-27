//
//  CBLQueryMeta.h
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
@class CBLQueryExpression;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLQueryMeta is a factory class for creating the expressions that refers to
 the metadata properties of the document.
 */
@interface CBLQueryMeta : NSObject

/**
 Document ID expression.

 @return The document ID expression.
 */
+ (CBLQueryExpression*) id;

/**
 Document ID expression.

 @param alias The data source alias name.
 @return The document ID expression.
 */
+ (CBLQueryExpression*) idFrom: (nullable NSString*)alias;

/**
 Sequence number expression. The sequence number indicates how recently
 the document has been changed. If one document's `sequence` is greater
 than another's, that means it was changed more recently.

 @return The sequence number expression.
 */
+ (CBLQueryExpression*) sequence;

/**
 Sequence number expression. The sequence number indicates how recently
 the document has been changed. If one document's `sequence` is greater
 than another's, that means it was changed more recently.

 @param alias The data source alias name.
 @return The sequence number expression.
 */
+ (CBLQueryExpression*) sequenceFrom: (nullable NSString*)alias;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
