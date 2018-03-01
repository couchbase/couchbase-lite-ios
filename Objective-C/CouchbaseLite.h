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

#import "CBLArray.h"
#import "CBLArrayFragment.h"
#import "CBLAuthenticator.h"
#import "CBLBasicAuthenticator.h"
#import "CBLBlob.h"
#import "CBLDatabase.h"
#import "CBLDatabaseChange.h"
#import "CBLDatabaseConfiguration.h"
#import "CBLDatabaseEndpoint.h"
#import "CBLDictionary.h"
#import "CBLDictionaryFragment.h"
#import "CBLDocument.h"
#import "CBLDocumentChange.h"
#import "CBLDocumentFragment.h"
#import "CBLEndpoint.h"
#import "CBLErrors.h"
#import "CBLFragment.h"
#import "CBLFullTextIndex.h"
#import "CBLIndex.h"
#import "CBLIndexBuilder.h"
#import "CBLListenerToken.h"
#import "CBLQueryChange.h"
#import "CBLMutableArray.h"
#import "CBLMutableArrayFragment.h"
#import "CBLMutableDictionary.h"
#import "CBLMutableDictionaryFragment.h"
#import "CBLMutableDocument.h"
#import "CBLMutableFragment.h"
#import "CBLQuery.h"
#import "CBLQueryArrayExpression.h"
#import "CBLQueryArrayFunction.h"
#import "CBLQueryBuilder.h"
#import "CBLQueryCollation.h"
#import "CBLQueryDataSource.h"
#import "CBLQueryExpression.h"
#import "CBLQueryFunction.h"
#import "CBLQueryFullTextExpression.h"
#import "CBLQueryFullTextFunction.h"
#import "CBLQueryJoin.h"
#import "CBLQueryLimit.h"
#import "CBLQueryMeta.h"
#import "CBLQueryOrdering.h"
#import "CBLQueryParameters.h"
#import "CBLQueryResult.h"
#import "CBLQueryResultSet.h"
#import "CBLQueryRow.h"
#import "CBLQuerySelectResult.h"
#import "CBLQueryVariableExpression.h"
#import "CBLReplicator.h"
#import "CBLReplicatorChange.h"
#import "CBLReplicatorConfiguration.h"
#import "CBLSessionAuthenticator.h"
#import "CBLURLEndpoint.h"
#import "CBLValueIndex.h"
