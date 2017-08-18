//
//  CBLDocument+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "CBLArray.h"
#import "CBLBlob.h"
#import "CBLC4Document.h"
#import "CBLDatabase.h"
#import "CBLDictionary.h"
#import "CBLDocument.h"
#import "CBLDocumentFragment.h"
#import "CBLFLArray.h"
#import "CBLFLDict.h"
#import "CBLFragment.h"
#import "CBLReadOnlyArray.h"
#import "CBLReadOnlyDocument.h"
#import "CBLReadOnlyDictionary.h"
#import "CBLReadOnlyFragment.h"
#import "Fleece.h"


NS_ASSUME_NONNULL_BEGIN

//////////////////

@interface CBLDocument ()

@property (atomic) CBLDictionary* dict;

- (BOOL) save: (NSError**)error;

- (BOOL) deleteDocument: (NSError**)error;

- (BOOL) purge: (NSError**)error;

@end

//////////////////

@interface CBLReadOnlyDocument ()

@property (atomic, nullable) CBLDatabase* database;

@property (atomic, readonly) C4Database* c4db;   // Throws assertion-failure if null

@property (atomic, nullable) CBLC4Document* c4Doc;

@property (atomic, readonly) BOOL exists;

@property (atomic, readonly) NSString* revID;

@property (atomic, readonly) NSUInteger generation;

@property (atomic, readonly) id<CBLConflictResolver> effectiveConflictResolver;

- (instancetype) initWithDatabase: (nullable CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable CBLFLDict*)data NS_DESIGNATED_INITIALIZER;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (BOOL) selectConflictingRevision;
- (BOOL) selectCommonAncestorOfDoc: (CBLReadOnlyDocument*)doc1
                            andDoc: (CBLReadOnlyDocument*)doc2;

- (nullable NSData*) encode: (NSError**)outError;

@end

//////////////////

@interface CBLDictionary ()

@property (atomic, readonly) BOOL changed;

@end

//////////////////

@interface CBLReadOnlyArray ()

@property (atomic, readonly, nullable) CBLFLArray* data;

- (instancetype) initWithFleeceData: (nullable CBLFLArray*)data;

@end

//////////////////

@interface CBLReadOnlyDictionary ()

@property (atomic, nullable) CBLFLDict* data;

@property (atomic, readonly) BOOL isEmpty;

@property (nonatomic, readonly) NSObject* lock;

- (instancetype) initWithFleeceData: (nullable CBLFLDict*)data;

@end

/////////////////

@interface CBLReadOnlyFragment ()

- (instancetype) initWithValue: (nullable id)value;

@end

/////////////////

@interface CBLFragment ()

- (instancetype) initWithValue: (nullable id)value
                        parent: (nullable id)parent
                     parentKey: (nullable id)parentKey;

@end

/////////////////

@interface CBLDocumentFragment ()

- (instancetype) initWithDocument: (CBLDocument*)document;

@end

NS_ASSUME_NONNULL_END
