//
//  CBLConflict.h
//  CouchbaseLite
//
//  Copyright (c) 2024 Couchbase, Inc All rights reserved.
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

@class CBLDocument;

NS_ASSUME_NONNULL_BEGIN

/**
 Conflict class, which includes the conflicted documents. 
 */
@interface CBLConflict : NSObject

/** The document id of the conflicting document */
@property(nonatomic, readonly) NSString* documentID;

/** The document in the local database. If nil, document is deleted. */
@property(nonatomic, readonly, nullable) CBLDocument* localDocument;

/** The document replicated from the remote database. If nil, document is deleted. */
@property(nonatomic, readonly, nullable) CBLDocument* remoteDocument;

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
