//
//  CBLDocument.h
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
#import "CBLDictionary.h"
@class CBLMutableDocument;

NS_ASSUME_NONNULL_BEGIN

/** A Couchbase Lite document. The CBLDocument is immutable. */
@interface CBLDocument : NSObject <CBLDictionary, NSMutableCopying>

/** The document's ID. */
@property (readonly, nonatomic) NSString* id;

/** 
 Sequence number of the document in the database.
 This indicates how recently the document has been changed: every time any document is updated,
 the database assigns it the next sequential sequence number. Thus, if a document's `sequence`
 property changes that means it's been changed (on-disk); and if one document's `sequence`
 is greater than another's, that means it was changed more recently.
 */
@property (readonly, nonatomic) uint64_t sequence;

/**
 Returns a mutable copy of the document.
 
 @return The CBLMutableDocument object.
 */
- (CBLMutableDocument*) toMutable;

- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
