//
//  CouchbaseLite.h
//  CouchbaseLite
//
//  Copyright (c) 2016 Couchbase, Inc All rights reserved.
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

//! Project version number for CouchbaseLite.
FOUNDATION_EXPORT double CouchbaseLiteVersionNumber;

//! Project version string for CouchbaseLite.
FOUNDATION_EXPORT const unsigned char CouchbaseLiteVersionString[];

#import <CouchbaseLite/CBLArray.h>
#import <CouchbaseLite/CBLArrayFragment.h>
#import <CouchbaseLite/CBLAuthenticator.h>
#import <CouchbaseLite/CBLBasicAuthenticator.h>
#import <CouchbaseLite/CBLBlob.h>
#import <CouchbaseLite/CBLCollection.h>
#import <CouchbaseLite/CBLCollectionChange.h>
#import <CouchbaseLite/CBLCollectionChangeObservable.h>
#import <CouchbaseLite/CBLCollectionConfiguration.h>
#import <CouchbaseLite/CBLConflict.h>
#import <CouchbaseLite/CBLConflictResolver.h>
#import <CouchbaseLite/CBLConsoleLogger.h>
#import <CouchbaseLite/CBLDatabase.h>
#import <CouchbaseLite/CBLDatabaseChange.h>
#import <CouchbaseLite/CBLDatabaseConfiguration.h>
#import <CouchbaseLite/CBLDictionary.h>
#import <CouchbaseLite/CBLDictionaryFragment.h>
#import <CouchbaseLite/CBLDocument.h>
#import <CouchbaseLite/CBLDocumentChange.h>
#import <CouchbaseLite/CBLDocumentFlags.h>
#import <CouchbaseLite/CBLDocumentFragment.h>
#import <CouchbaseLite/CBLDocumentReplication.h>
#import <CouchbaseLite/CBLEdition.h>
#import <CouchbaseLite/CBLEndpoint.h>
#import <CouchbaseLite/CBLErrors.h>
#import <CouchbaseLite/CBLFileLogger.h>
#import <CouchbaseLite/CBLFragment.h>
#import <CouchbaseLite/CBLFullTextIndex.h>
#import <CouchbaseLite/CBLIndex.h>
#import <CouchbaseLite/CBLIndexable.h>
#import <CouchbaseLite/CBLIndexBuilder.h>
#import <CouchbaseLite/CBLListenerToken.h>
#import <CouchbaseLite/CBLLog.h>
#import <CouchbaseLite/CBLLogger.h>
#import <CouchbaseLite/CBLLogFileConfiguration.h>
#import <CouchbaseLite/CBLQueryChange.h>
#import <CouchbaseLite/CBLMutableArray.h>
#import <CouchbaseLite/CBLMutableArrayFragment.h>
#import <CouchbaseLite/CBLMutableDictionary.h>
#import <CouchbaseLite/CBLMutableDictionaryFragment.h>
#import <CouchbaseLite/CBLMutableDocument.h>
#import <CouchbaseLite/CBLMutableFragment.h>
#import <CouchbaseLite/CBLQuery.h>
#import <CouchbaseLite/CBLQueryArrayExpression.h>
#import <CouchbaseLite/CBLQueryArrayFunction.h>
#import <CouchbaseLite/CBLQueryBuilder.h>
#import <CouchbaseLite/CBLQueryCollation.h>
#import <CouchbaseLite/CBLQueryDataSource.h>
#import <CouchbaseLite/CBLQueryExpression.h>
#import <CouchbaseLite/CBLQueryFactory.h>
#import <CouchbaseLite/CBLQueryFunction.h>
#import <CouchbaseLite/CBLQueryFullTextExpression.h>
#import <CouchbaseLite/CBLQueryFullTextFunction.h>
#import <CouchbaseLite/CBLQueryJoin.h>
#import <CouchbaseLite/CBLQueryLimit.h>
#import <CouchbaseLite/CBLQueryMeta.h>
#import <CouchbaseLite/CBLQueryOrdering.h>
#import <CouchbaseLite/CBLQueryParameters.h>
#import <CouchbaseLite/CBLQueryResult.h>
#import <CouchbaseLite/CBLQueryResultSet.h>
#import <CouchbaseLite/CBLQuerySelectResult.h>
#import <CouchbaseLite/CBLQueryVariableExpression.h>
#import <CouchbaseLite/CBLReplicator.h>
#import <CouchbaseLite/CBLReplicatorChange.h>
#import <CouchbaseLite/CBLReplicatorConfiguration.h>
#import <CouchbaseLite/CBLScope.h>
#import <CouchbaseLite/CBLSessionAuthenticator.h>
#import <CouchbaseLite/CBLURLEndpoint.h>
#import <CouchbaseLite/CBLValueIndex.h>
#import <CouchbaseLite/CBLIndexConfiguration.h>
#import <CouchbaseLite/CBLFullTextIndexConfiguration.h>
#import <CouchbaseLite/CBLValueIndexConfiguration.h>
#import <CouchbaseLite/CBLCollectionTypes.h>
#import <CouchbaseLite/CBLDefaults.h>
#import <CouchbaseLite/CBLQueryFullTextIndexExpressionProtocol.h>

#ifdef COUCHBASE_ENTERPRISE

#import <CouchbaseLite/CBLCoreMLPredictiveModel.h>
#import <CouchbaseLite/CBLClientCertificateAuthenticator.h>
#import <CouchbaseLite/CBLDatabase+Encryption.h>
#import <CouchbaseLite/CBLDatabase+Prediction.h>
#import <CouchbaseLite/CBLDatabaseConfiguration+Encryption.h>
#import <CouchbaseLite/CBLDatabaseEndpoint.h>
#import <CouchbaseLite/CBLEncryptionKey.h>
#import <CouchbaseLite/CBLIndexBuilder+Prediction.h>
#import <CouchbaseLite/CBLListenerAuthenticator.h>
#import <CouchbaseLite/CBLListenerCertificateAuthenticator.h>
#import <CouchbaseLite/CBLListenerPasswordAuthenticator.h>
#import <CouchbaseLite/CBLMessage.h>
#import <CouchbaseLite/CBLMessageEndpoint.h>
#import <CouchbaseLite/CBLMessageEndpointConnection.h>
#import <CouchbaseLite/CBLMessageEndpointListener.h>
#import <CouchbaseLite/CBLMessagingError.h>
#import <CouchbaseLite/CBLPrediction.h>
#import <CouchbaseLite/CBLPredictiveIndex.h>
#import <CouchbaseLite/CBLProtocolType.h>
#import <CouchbaseLite/CBLQueryFunction+Prediction.h>
#import <CouchbaseLite/CBLQueryFunction+Vector.h>
#import <CouchbaseLite/CBLReplicatorConfiguration+ServerCert.h>
#import <CouchbaseLite/CBLTLSIdentity.h>
#import <CouchbaseLite/CBLURLEndpointListener.h>
#import <CouchbaseLite/CBLURLEndpointListenerConfiguration.h>
#import <CouchbaseLite/CBLVectorEncoding.h>
#import <CouchbaseLite/CBLVectorIndexConfiguration.h>
#import <CouchbaseLite/CBLVectorIndexTypes.h>

#endif
