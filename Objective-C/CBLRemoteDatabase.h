//
//  CBLRemoteDatabase.h
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
#import "CBLAuthenticator.h"
#import "CBLDocument.h"

@class CBLDatabaseChange;

NS_ASSUME_NONNULL_BEGIN

@interface CBLRemoteDatabase : NSObject

/** Completion blocks. */
typedef void (^CBLGetDocumentCompletion)(CBLDocument* _Nullable, NSError* _Nullable);
typedef void (^CBLPutDocumentCompletion)(CBLDocument* _Nullable, NSError* _Nullable);
typedef void (^CBLDocChangeListener)(CBLDatabaseChange*);

/** Creates a new RemoteDatabase instance, and starts it automatically. */
- (instancetype) initWithURL: (NSURL*)url authenticator: (nullable CBLAuthenticator*)authenticator;

/** Gets an existing document with the given ID. If a document with the given ID
    doesn't exist in the database, the value returned will be nil. */
- (void) documentWithID: (NSString*)identifier
             completion: (CBLGetDocumentCompletion)completion;

/** Stop and close the connection with the remote database. */
- (void) stop;

/** Saves a document to the remote database. */
- (void) saveDocument: (CBLMutableDocument *)document
           completion: (CBLPutDocumentCompletion)completion;

/** Deletes a document from the remote database. */
- (void) deleteDocument: (CBLDocument *)document
             completion: (CBLPutDocumentCompletion)completion;

/** */
- (void) addChangeListener: (CBLDocChangeListener)listener;

@end

NS_ASSUME_NONNULL_END
