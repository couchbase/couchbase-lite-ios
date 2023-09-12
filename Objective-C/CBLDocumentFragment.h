//
//  CBLDocumentFragment.h
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
#import "CBLDictionaryFragment.h"
@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/** 
 CBLDocumentFragment provides access to a document object. CBLDocumentFragment also provides
 subscript access by either key or index to the data values of the document which are
 wrapped by CBLFragment objects.
 */
@interface CBLDocumentFragment : NSObject <CBLDictionaryFragment>

/** Checks whether the document exists in the database or not. */
@property (nonatomic, readonly) BOOL exists;

/** Gets the document from the document fragment object. */
@property (nonatomic, readonly, nullable) CBLDocument* document;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
