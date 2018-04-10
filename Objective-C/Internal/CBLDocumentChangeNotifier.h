//
//  CBLDocumentChangeNotifier.h
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc All rights reserved.
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

#import "CBLChangeNotifier.h"
@class CBLDatabase;
@class CBLDocumentChange;

NS_ASSUME_NONNULL_BEGIN


/**
 A subclass of CBLChangeNotifier that manages document change notifications.
 It manages the underlying C4DocumentObserver and posts the CBLDocumentChange notifications itself.
*/
@interface CBLDocumentChangeNotifier : CBLChangeNotifier<CBLDocumentChange*>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       documentID: (NSString*)documentID;

/** Immediately stops the C4DocumentObserver. No more notifications will be sent. */
- (void) stop;

@end

NS_ASSUME_NONNULL_END
