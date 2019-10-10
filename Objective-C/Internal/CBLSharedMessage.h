//
//  CBLSharedMessage.h
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

@interface CBLSharedMessage : NSObject

extern NSString* const kCBLMessageCreateDBDirectoryFailed;
extern NSString* const kCBLMessageCloseDBFailedReplications;
extern NSString* const kCBLMessageCloseDBFailedQueryListeners;
extern NSString* const kCBLMessageDeleteDBFailedReplications;
extern NSString* const kCBLMessageDeleteDBFailedQueryListeners;
extern NSString* const kCBLMessageDeleteDocFailedNotSaved;
extern NSString* const kCBLMessageDocumentNotFound;
extern NSString* const kCBLMessageDocumentAnotherDatabase;
extern NSString* const kCBLMessageBlobDifferentDatabase;
extern NSString* const kCBLMessageBlobContentNull;
extern NSString* const kCBLMessageResolvedDocContainsNull;
extern NSString* const kCBLMessageResolvedDocFailedLiteCore;
extern NSString* const kCBLMessageResolvedDocWrongDb;
extern NSString* const kCBLMessageDBClosed;
extern NSString* const kCBLMessageNoDocumentRevision;
extern NSString* const kCBLMessageFragmentPathNotExist;
extern NSString* const kCBLMessageInvalidCouchbaseObjType;
extern NSString* const kCBLMessageInvalidValueToBeDeserialized;
extern NSString* const kCBLMessageBlobContainsNoData;
extern NSString* const kCBLMessageNotFileBasedURL;
extern NSString* const kCBLMessageBlobReadStreamNotOpen;
extern NSString* const kCBLMessageCannotSetLogLevel;
extern NSString* const kCBLMessageInvalidSchemeURLEndpoint;
extern NSString* const kCBLMessageInvalidEmbeddedCredentialsInURL;
extern NSString* const kCBLMessageReplicatorNotStopped;
extern NSString* const kCBLMessageQueryParamNotAllowedContainCollections;
extern NSString* const kCBLMessageMissASforJoin;
extern NSString* const kCBLMessageMissONforJoin;
extern NSString* const kCBLMessageExpressionsMustBeIExpressionOrString;
extern NSString* const kCBLMessageInvalidExpressionValueBetween;
extern NSString* const kCBLMessageResultSetAlreadyEnumerated;
extern NSString* const kCBLMessageExpressionsMustContainOnePlusElement;
extern NSString* const kCBLMessageDuplicateSelectResultName;
extern NSString* const kCBLMessageNoAliasInJoin;
extern NSString* const kCBLMessageInvalidQueryDBNull;
extern NSString* const kCBLMessageInvalidQueryMissingSelectOrFrom;
extern NSString* const kCBLMessagePullOnlyPendingDocIDs;

@end

NS_ASSUME_NONNULL_END

