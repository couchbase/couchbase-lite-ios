//
//  CBLDocument+Internal.h
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
#import "CBLMutableArray.h"
#import "CBLBlob.h"
#import "CBLC4Document.h"
#import "CBLDatabase.h"
#import "CBLMutableDictionary.h"
#import "CBLMutableDocument.h"
#import "CBLDocumentFragment.h"
#import "CBLMutableFragment.h"
#import "CBLArray.h"
#import "CBLDocument.h"
#import "CBLDictionary.h"
#import "CBLFragment.h"
#import "fleece/Fleece.h"


NS_ASSUME_NONNULL_BEGIN

//////////////////

@interface CBLMutableDocument ()

- (instancetype) initAsCopyWithDocument: (CBLDocument*)doc
                                   dict: (nullable CBLDictionary*)dict;

@end

//////////////////

@interface CBLDocument ()
{
    @protected
    CBLDictionary* _dict;
    BOOL _isInvalidated;
    NSString* _revID;
}

@property (nonatomic, nullable) CBLCollection* collection;

@property (nonatomic, readonly) C4Database* c4db;

@property (atomic, nullable) CBLC4Document* c4Doc;

@property (nonatomic, readonly) BOOL isEmpty;

@property (readonly, nonatomic) BOOL isDeleted;

@property (nonatomic, readonly, nullable) FLDict fleeceData;

- (instancetype) initWithCollection: (nullable CBLCollection*)collection
                         documentID: (NSString*)documentID
                              c4Doc: (nullable CBLC4Document*)c4Doc NS_DESIGNATED_INITIALIZER;

- (instancetype) initWithCollection: (CBLCollection*)collection
                         documentID: (NSString*)documentID
                         revisionID: (NSString*)revisionID
                               body: (nullable FLDict)body;

- (nullable instancetype) initWithCollection: (CBLCollection*)collection
                                  documentID: (NSString*)documentID
                              includeDeleted: (BOOL)includeDeleted
                                       error: (NSError**)outError;

- (nullable instancetype) initWithCollection: (CBLCollection*)collection
                                  documentID: (NSString*)documentID
                              includeDeleted: (BOOL)includeDeleted
                                contentLevel: (C4DocContentLevel)contentLevel
                                       error: (NSError**)outError;

- (BOOL) selectConflictingRevision;
- (BOOL) selectCommonAncestorOfDoc: (CBLDocument*)doc1
                            andDoc: (CBLDocument*)doc2;

// Encodes the document and returns the corresponding slice
//
//  - outRevFlags: Attachment flag will be set, if any present.
//  - error: On return, the error if any.
- (FLSliceResult) encodeWithRevFlags: (C4RevisionFlags*)outRevFlags
                               error: (NSError**)outError;

- (void) setEncodingError: (NSError*)error;

// Replace c4doc without updating the document data
- (void) replaceC4Doc: (nullable CBLC4Document*)c4doc;

@end

//////////////////

@interface CBLMutableDictionary ()

@property (readonly, nonatomic) BOOL changed;

@end

//////////////////

@interface CBLArray ()

@property (atomic, readonly) NSObject* sharedLock;

- (instancetype) initEmpty;

@end

//////////////////

@interface CBLDictionary ()

@property (atomic, readonly) NSObject* sharedLock;

- (instancetype) initEmpty;
- (void) keysChanged;

@end

/////////////////

@interface CBLFragment ()
{
    @protected
    id _parent;
    NSString* _key;           // Nil if this is an indexed subscript
    NSUInteger _index;        // Ignored if this is a keyed subscript
}

- (instancetype) initWithParent: (id)parent key: (NSString*)parentKey;
- (instancetype) initWithParent: (id)parent index: (NSUInteger)parentIndex;

@end

/////////////////

@interface CBLDocumentFragment ()

- (instancetype) initWithDocument: (nullable CBLDocument*)document;

@end

NS_ASSUME_NONNULL_END
