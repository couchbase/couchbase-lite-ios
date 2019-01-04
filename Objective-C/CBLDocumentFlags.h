//
//  CBLDocumentFlags.h
//  CouchbaseLite
//
//  Copyright (c) 2017 Couchbase, Inc All rights reserved.
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

#pragma once

/** Document flags describing a replicated document. */
typedef NS_OPTIONS(NSUInteger, CBLDocumentFlags) {
    kCBLDocumentFlagsDeleted        = 1 << 0,   ///< Indicating that the replicated document has been deleted.
    kCBLDocumentFlagsAccessRemoved  = 1 << 1    ///< Indicating that the document's access has been removed as a result of
                                                ///  removal from all Sync Gateway channels that a user has access to.
};
