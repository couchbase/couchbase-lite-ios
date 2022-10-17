//
//  CBLRemoteDocument.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Interface used by the remote database */
@interface CBLRemoteDocument : NSObject

/** if the document is remoteDoc, this contains the document body */
@property (nonatomic, readonly) FLSliceResult body;
@property (nonatomic, readonly) FLDict data;

/**
 This constructor is used by ConnectedClient APIs.
 Used to create a CBLDocument without database and c4doc
 Will retain the passed in `body`(FLSliceResult) */
- (instancetype) initWithBody: (FLSliceResult)body;


@end

NS_ASSUME_NONNULL_END
