//
//  CBLQueryObserver.h
//  CouchbaseLite
//
//  Copyright (c) 2021 Couchbase, Inc All rights reserved.
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

@protocol CBLListenerToken;
@class CBLChangeListenerToken;
@class CBLChangeNotifier;
@class CBLQuery;
@class CBLQueryChange;

NS_ASSUME_NONNULL_BEGIN

@interface CBLQueryObserver : NSObject

- (instancetype) init NS_UNAVAILABLE; 

/** Initialize with a Query. */
- (instancetype) initWithQuery: (CBLQuery*)query
                   columnNames: (NSDictionary*)columnNames
                         token: (CBLChangeListenerToken*)token;

/** Starts the observer */
- (void) start;

/** Stops and frees the observer */
- (void) stop;

@end

NS_ASSUME_NONNULL_END
