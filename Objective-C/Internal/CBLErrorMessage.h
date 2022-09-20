//
//  CBLErrorMessage.h
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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CBLErrorMessage : NSObject

extern NSString* const kCBLErrorMessageCreateDBDirectoryFailed;
extern NSString* const kCBLErrorMessageCloseDBFailedReplications;
extern NSString* const kCBLErrorMessageCloseDBFailedQueryListeners;
extern NSString* const kCBLErrorMessageDeleteDBFailedReplications;
extern NSString* const kCBLErrorMessageDeleteDBFailedQueryListeners;
extern NSString* const kCBLErrorMessageDeleteDocFailedNotSaved;
extern NSString* const kCBLErrorMessageDocumentNotFound;
extern NSString* const kCBLErrorMessageDocumentAnotherDatabase;
extern NSString* const kCBLErrorMessageBlobDifferentDatabase;
extern NSString* const kCBLErrorMessageBlobContentNull;
extern NSString* const kCBLErrorMessageResolvedDocContainsNull;
extern NSString* const kCBLErrorMessageResolvedDocFailedLiteCore;
extern NSString* const kCBLErrorMessageResolvedDocWrongDb;
extern NSString* const kCBLErrorMessageDBClosedOrCollectionDeleted;
extern NSString* const kCBLErrorMessageNoDocumentRevision;
extern NSString* const kCBLErrorMessageFragmentPathNotExist;
extern NSString* const kCBLErrorMessageInvalidCouchbaseObjType;
extern NSString* const kCBLErrorMessageInvalidValueToBeDeserialized;
extern NSString* const kCBLErrorMessageBlobContainsNoData;
extern NSString* const kCBLErrorMessageNotFileBasedURL;
extern NSString* const kCBLErrorMessageBlobReadStreamNotOpen;
extern NSString* const kCBLErrorMessageCannotSetLogLevel;
extern NSString* const kCBLErrorMessageInvalidSchemeURLEndpoint;
extern NSString* const kCBLErrorMessageInvalidEmbeddedCredentialsInURL;
extern NSString* const kCBLErrorMessageReplicatorNotStopped;
extern NSString* const kCBLErrorMessageQueryParamNotAllowedContainCollections;
extern NSString* const kCBLErrorMessageMissASforJoin;
extern NSString* const kCBLErrorMessageMissONforJoin;
extern NSString* const kCBLErrorMessageExpressionsMustBeIExpressionOrString;
extern NSString* const kCBLErrorMessageInvalidExpressionValueBetween;
extern NSString* const kCBLErrorMessageResultSetAlreadyEnumerated;
extern NSString* const kCBLErrorMessageExpressionsMustContainOnePlusElement;
extern NSString* const kCBLErrorMessageDuplicateSelectResultName;
extern NSString* const kCBLErrorMessageNoAliasInJoin;
extern NSString* const kCBLErrorMessageInvalidQueryDBNull;
extern NSString* const kCBLErrorMessageInvalidQueryMissingSelectOrFrom;
extern NSString* const kCBLErrorMessagePullOnlyPendingDocIDs;
extern NSString* const kCBLErrorMessageNoDocEditInReplicationFilter;
extern NSString* const kCBLErrorMessageIdentityNotFound;
extern NSString* const kCBLErrorMessageFailToConvertC4Cert;
extern NSString* const kCBLErrorMessageDuplicateCertificate;
extern NSString* const kCBLErrorMessageMissingCommonName;
extern NSString* const kCBLErrorMessageFailToRemoveKeyPair;
extern NSString* const kCBLErrorMessageDocumentNotFoundInCollection;
extern NSString* const kCBLErrorMessageDocumentAnotherCollection;
extern NSString* const kCBLErrorMessageInvalidBlob;
extern NSString* const kCBLErrorMessageCollectionNotFoundDuringConflict;
extern NSString* const kCBLErrorMessageConfigNotFoundDuringConflict;
extern NSString* const kCBLErrorMessageCollectionNotFoundInFilter;
extern NSString* const kCBLErrorMessageQueryFromInvalidDB;
extern NSString* const kCBLErrorMessageEncodeFailureInvalidQuery;
extern NSString* const kCBLErrorMessageNoDefaultCollectionInConfig;
extern NSString* const kCBLErrorMessageNegativeHeartBeat;
extern NSString* const kCBLErrorMessageNegativeMaxAttemptWaitTime;
extern NSString* const kCBLErrorMessageAccessDBWithoutCollection;
extern NSString* const kCBLErrorMessageAddInvalidCollection;
extern NSString* const kCBLErrorMessageAddCollectionFromAnotherDB;
extern NSString* const kCBLErrorMessageAddEmptyCollectionArray;

@end

NS_ASSUME_NONNULL_END

