//
//  CBLErrorMessage.m
//  CouchbaseLite
//
//  Copyright (c) 2019 Couchbase, Inc All rights reserved.
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
 
#import "CBLErrorMessage.h"
 
@implementation CBLErrorMessage
 
NSString* const kCBLErrorMessageCreateDBDirectoryFailed = @"Unable to create database directory.";
NSString* const kCBLErrorMessageCloseDBFailedReplications = @"Cannot close the database. Please stop all of the replicators before closing the database.";
NSString* const kCBLErrorMessageCloseDBFailedQueryListeners = @"Cannot close the database. Please remove all of the query listeners before closing the database.";
NSString* const kCBLErrorMessageDeleteDBFailedReplications = @"Cannot delete the database. Please stop all of the replicators before closing the database.";
NSString* const kCBLErrorMessageDeleteDBFailedQueryListeners = @"Cannot delete the database. Please remove all of the query listeners before closing the database.";
NSString* const kCBLErrorMessageDeleteDocFailedNotSaved = @"Cannot delete a document that has not yet been saved.";
NSString* const kCBLErrorMessageDocumentNotFound = @"The document doesn't exist in the database.";
NSString* const kCBLErrorMessageDocumentAnotherDatabase = @"Cannot operate on a document from another database.";
NSString* const kCBLErrorMessageBlobDifferentDatabase = @"A document contains a blob that was saved to a different database. The save operation cannot complete.";
NSString* const kCBLErrorMessageBlobContentNull = @"No data available to write for install. Please ensure that all blobs in the document have non-null content.";
NSString* const kCBLErrorMessageResolvedDocContainsNull = @"Resolved document has a null body.";
NSString* const kCBLErrorMessageResolvedDocFailedLiteCore = @"LiteCore failed resolving conflict.";
NSString* const kCBLErrorMessageResolvedDocWrongDb = @"Resolved document's database %1$@ is different from expected database %2$@.";
NSString* const kCBLErrorMessageDBClosed = @"Attempt to perform an operation on a closed database.";
NSString* const kCBLErrorMessageNoDocumentRevision = @"No revision data on the document!";
NSString* const kCBLErrorMessageFragmentPathNotExist = @"Specified fragment path does not exist in object; cannot set value.";
NSString* const kCBLErrorMessageInvalidCouchbaseObjType = @"%1$@ is not a valid type. You may only pass %2$@, Blob, a one-dimensional array or a dictionary whose members are one of the preceding types.";
NSString* const kCBLErrorMessageInvalidValueToBeDeserialized = @"Non-string or null key in data to be deserialized.";
NSString* const kCBLErrorMessageBlobContainsNoData = @"Blob has no data available.";
NSString* const kCBLErrorMessageNotFileBasedURL = @"%1$@ must be a file-based URL.";
NSString* const kCBLErrorMessageBlobReadStreamNotOpen = @"Stream is not open.";
NSString* const kCBLErrorMessageCannotSetLogLevel = @"Cannot set logging level without a configuration.";
NSString* const kCBLErrorMessageInvalidSchemeURLEndpoint = @"Invalid scheme for URLEndpoint url (%1$@). It must be either 'ws:' or 'wss:'.";
NSString* const kCBLErrorMessageInvalidEmbeddedCredentialsInURL = @"Embedded credentials in a URL (username:password@url) are not allowed. Use the BasicAuthenticator class instead.";
NSString* const kCBLErrorMessageReplicatorNotStopped = @"Replicator is not stopped. Resetting checkpoint is only allowed when the replicator is in the stopped state.";
NSString* const kCBLErrorMessageQueryParamNotAllowedContainCollections = @"Query parameters are not allowed to contain collections.";
NSString* const kCBLErrorMessageMissASforJoin = @"Missing AS clause for JOIN.";
NSString* const kCBLErrorMessageMissONforJoin = @"Missing ON statement for JOIN.";
NSString* const kCBLErrorMessageExpressionsMustBeIExpressionOrString = @"Expressions must either be %1$@ or String.";
NSString* const kCBLErrorMessageInvalidExpressionValueBetween = @"Invalid expression value for expression of Between(%1$@).";
NSString* const kCBLErrorMessageResultSetAlreadyEnumerated = @"This result set has already been enumerated. Please re-execute the original query.";
NSString* const kCBLErrorMessageExpressionsMustContainOnePlusElement = @"%1$@ expressions must contain at least one element.";
NSString* const kCBLErrorMessageDuplicateSelectResultName = @"Duplicate select result named %1$@.";
NSString* const kCBLErrorMessageNoAliasInJoin = @"The default database must have an alias in order to use a JOIN statement (Make sure your data source uses the As() function).";
NSString* const kCBLErrorMessageInvalidQueryDBNull = @"Invalid query: The database is null.";
NSString* const kCBLErrorMessageInvalidQueryMissingSelectOrFrom = @"Invalid query: missing Select or From.";
NSString* const kCBLErrorMessagePullOnlyPendingDocIDs = @"Pending Document IDs are not supported on pull-only replicators.";

@end

