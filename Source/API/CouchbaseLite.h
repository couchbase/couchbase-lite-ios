//
//  CouchbaseLite.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.


#define CBL_DEPRECATED  // Enable deprecated methods.

#import "CBLManager.h"
#import "CBLDatabase.h"
#import "CBLDatabaseChange.h"
#import "CBLDocument.h"
#import "CBLRevision.h"
#import "CBLAttachment.h"
#import "CBLView.h"
#import "CBLQuery.h"
#import "CBLQuery+FullTextSearch.h"
#import "CBLQuery+Geo.h"
#import "CBLAuthenticator.h"
#import "CBLReplication.h"
#import "CBLModel.h"
#import "CBLModelFactory.h"
#import "CBLJSON.h"

#if TARGET_OS_IPHONE
#import "CBLUITableSource.h"
#endif
