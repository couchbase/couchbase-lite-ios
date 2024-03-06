//
//  CBLCollection.h
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

#import <CouchbaseLite/CBLCollectionChangeObservable.h>
#import <CouchbaseLite/CBLIndexable.h>
#import <CouchbaseLite/CBLCollectionTypes.h>

@class CBLDatabase;
@class CBLDocument;
@class CBLDocumentChange;
@class CBLDocumentFragment;
@class CBLMutableDocument;
@class CBLScope;
@protocol CBLListenerToken;

NS_ASSUME_NONNULL_BEGIN

/** The default collection name constant */
extern NSString* const kCBLDefaultCollectionName;

/**
 A `CBLCollection` represent a collection which is a container for documents.
 
 A collection can be thought as a table in the relational database. Each collection belongs to
 a scope which is simply a namespace, and has a name which is unique within its scope.
 
 When a new database is created, a default collection named "_default" will be automatically
 created. The default collection is created under the default scope named "_default".
 The name of the default collection and scope can be referenced by using
 `kCBLDefaultCollectionName` and `kCBLDefaultScopeName` constant.
 
 @note The default collection cannot be deleted.
 
 When creating a new collection, the collection name, and the scope name are required.
 The naming rules of the collections and scopes are as follows:
 - Must be between 1 and 251 characters in length.
 - Can only contain the characters A-Z, a-z, 0-9, and the symbols _, -, and %.
 - Cannot start with _ or %.
 - Both scope and collection names are case sensitive.
 
 ##  `CBLCollection` Lifespan
 A `Collection` object and its reference remain valid until either the database is closed or
 the collection itself is deleted, in that case it will return
 CBLErrorNotOpen while accessing the collection APIs.

 ## Legacy Database and API
 When using the legacy database, the existing documents and indexes in the database will be
 automatically migrated to the default collection.
 
 Any pre-existing database functions that refer to documents, listeners, and indexes without
 specifying a collection such as \ref [database documentWithID:]] will implicitly operate on
 the default collection. In other words, they behave exactly the way they used to, but
 collection-aware code should avoid them and use the new Collection API instead.
 These legacy functions are deprecated and will be removed eventually.
 */
@interface CBLCollection : NSObject<CBLCollectionChangeObservable, CBLIndexable, NSCopying>

/** Collection's name.*/
@property (readonly, nonatomic) NSString* name;

/** Collection's fully qualified name in the '<scope-name>.<collection-name>' format. */
@property (readonly, nonatomic) NSString* fullName;

/** Collection's scope. */
@property (readonly, nonatomic) CBLScope* scope;

/** Collection's database. */
@property (readonly, nonatomic) CBLDatabase* database;

#pragma mark - Document Management

/** The number of documents in the collection. */
@property (readonly, atomic) uint64_t count;

/**
 Gets an existing document with the given ID. If a document with the given ID
 doesn't exist in the collection, the value returned will be nil.
 
 @param documentID The document ID.
 @param error On return, the error if any.
 @return The CBLDocument object.
 */
- (nullable CBLDocument*) documentWithID: (NSString*)documentID
                                   error: (NSError**)error NS_SWIFT_NOTHROW;

#pragma mark - Subscript

/**
 Gets a document fragment with the given document ID.
 
 @param documentID The document ID.
 @return The CBLDocumentFragment object.
 */
- (CBLDocumentFragment*) objectForKeyedSubscript: (NSString*)documentID;

#pragma mark - Save, Delete, Purge

/**
 Save a document into the collection. The default concurrency control, lastWriteWins,
 will be used when there is conflict during  save.
 
 When saving a document that already belongs to a collection, the collection instance of
 the document and this collection instance must be the same, otherwise, the InvalidParameter
 error will be thrown.
 
 @param document The document.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) saveDocument: (CBLMutableDocument*)document error: (NSError**)error;

/**
 Save a document into the collection with a specified concurrency control. When specifying
 the failOnConflict concurrency control, and conflict occurred, the save operation will fail with
 'false' value returned.
 
 When saving a document that already belongs to a collection, the collection instance of the
 document and this collection instance must be the same, otherwise, the InvalidParameter
 error will be thrown.
 
 @param document The document.
 @param concurrencyControl The concurrency control.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) saveDocument: (CBLMutableDocument*)document
   concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                error: (NSError**)error NS_SWIFT_NOTHROW;

/**
 Save a document into the collection with a specified conflict handler. The specified conflict handler
 will be called if there is conflict during save. If the conflict handler returns 'false', the save operation
 will be canceled with 'false' value returned.
 
 When saving a document that already belongs to a collection, the collection instance of the
 document and this collection instance must be the same, otherwise, the InvalidParameter error
 will be thrown.
 
 @param document The document.
 @param conflictHandler The conflict handler block which can be used to resolve it.
 @param error On return, error if any.
 @return True if successful. False if there is a conflict, but the conflict wasn't resolved as the
    conflict handler returns 'false' value.
*/
- (BOOL) saveDocument: (CBLMutableDocument*)document
      conflictHandler: (BOOL (^)(CBLMutableDocument*, CBLDocument* nullable))conflictHandler
                error: (NSError**)error NS_SWIFT_NOTHROW;

/**
 Delete a document from the collection. The default concurrency control, lastWriteWins, will be used
 when there is conflict during delete. If the document doesn't exist in the collection, the NotFound
 error will be thrown.
 
 When deleting a document that already belongs to a collection, the collection instance of
 the document and this collection instance must be the same, otherwise, the InvalidParameter error
 will be thrown.
 
 @param document The document.
 @param error On return, the error if any.
 @return /True on success, false on failure.
 */
- (BOOL) deleteDocument: (CBLDocument*)document error: (NSError**)error;

/**
 Delete a document from the collection with a specified concurrency control. When specifying
 the failOnConflict concurrency control, and conflict occurred, the delete operation will fail with
 'false' value returned.
 
 When deleting a document, the collection instance of the document and this collection instance
 must be the same, otherwise, the InvalidParameter error will be thrown.
 
 @param document The document.
 @param concurrencyControl The concurrency control.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) deleteDocument: (CBLDocument*)document
     concurrencyControl: (CBLConcurrencyControl)concurrencyControl
                  error: (NSError**)error NS_SWIFT_NOTHROW;

/**
 When purging a document, the collection instance of the document and this collection instance
 must be the same, otherwise, the InvalidParameter error will be thrown.
 
 @param document The document to be purged.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) purgeDocument: (CBLDocument*)document error: (NSError**)error;


/**
 Purge a document by id from the collection. If the document doesn't exist in the collection,
 the NotFound error will be thrown.

 @param documentID The ID of the document to be purged.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) purgeDocumentWithID: (NSString*)documentID error: (NSError**)error;

#pragma mark - DOCUMENT EXPIRATION

/**
 Set an expiration date to the document of the given id.
 Setting a nil date will clear the expiration.
 
 @param documentID The ID of the document to set the expiration date for
 @param date The expiration date. Set nil date will reset the document expiration.
 @param error On return, the error if any.
 @return True on success, false on failure.
 */
- (BOOL) setDocumentExpirationWithID: (NSString*)documentID
                          expiration: (nullable NSDate*)date
                               error: (NSError**)error;

/**
 Get the expiration date set to the document of the given id.
 
 @param documentID The ID of the document to set the expiration date for
 @param error On return, the error if any.
 @return the expiration time of a document, if one has been set, else nil.
 */
- (nullable NSDate*) getDocumentExpirationWithID: (NSString*)documentID
                                           error: (NSError**)error NS_SWIFT_NOTHROW;

#pragma mark - Document change publisher

/**
 Add a change listener to listen to change events occurring to a document of the given document id.
 To remove the listener, call remove() function on the returned listener token.

 @param id The document ID.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
*/
- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)id
                                                listener: (void (^)(CBLDocumentChange*))listener;


/**
 Add a change listener to listen to change events occurring to a document of the given document id.
 If a dispatch queue is given, the events will be posted on the dispatch queue. To remove the listener,
 call remove() function on the returned listener token.

 @param documentID The document ID.
 @param queue The dispatch queue.
 @param listener The listener to post changes.
 @return An opaque listener token object for removing the listener.
 */
- (id<CBLListenerToken>) addDocumentChangeListenerWithID: (NSString*)documentID
                                                   queue: (nullable dispatch_queue_t)queue
                                                listener: (void (^)(CBLDocumentChange*))listener;

#pragma mark -

/** Not available */
- (instancetype) init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
