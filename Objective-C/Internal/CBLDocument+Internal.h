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

- (BOOL) save: (NSError**)error;

- (BOOL) deleteDocument: (NSError**)error;

- (BOOL) purge: (NSError**)error;

@end

//////////////////

@interface CBLReadOnlyDocument ()

@property (nonatomic, nullable) CBLDatabase* database;

@property (nonatomic, readonly) C4Database* c4db;   // Throws assertion-failure if null

@property (nonatomic, nullable) CBLC4Document* c4Doc;

@property (nonatomic, readonly) BOOL exists;

@property (nonatomic, readonly) NSString* revID;

@property (nonatomic, readonly) NSUInteger generation;

@property (nonatomic, readonly) id<CBLConflictResolver> effectiveConflictResolver;

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

@property (nonatomic) BOOL changed;

@end

//////////////////

@interface CBLReadOnlyArray ()

@property (nonatomic, readonly, nullable) CBLFLArray* data;

- (instancetype) initWithFleeceData: (nullable CBLFLArray*)data;

@end

//////////////////

@interface CBLReadOnlyDictionary ()

@property (nonatomic, nullable) CBLFLDict* data;

@property (nonatomic, readonly) BOOL isEmpty;

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
