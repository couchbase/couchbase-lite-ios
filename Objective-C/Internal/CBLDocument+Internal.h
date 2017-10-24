//
//  CBLDocument+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 4/14/17.
//  Copyright © 2017 Couchbase. All rights reserved.
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
#import "Fleece.h"


NS_ASSUME_NONNULL_BEGIN

//////////////////

@interface CBLMutableDocument ()

- (BOOL) save: (NSError**)error;

- (BOOL) deleteDocument: (NSError**)error;

- (BOOL) purge: (NSError**)error;

- (void) setEncodingError: (NSError*)error;

@end

//////////////////

@interface CBLDocument ()
{
    @protected
    CBLDictionary* _dict;
}

@property (nonatomic, nullable) CBLDatabase* database;

@property (nonatomic, readonly) C4Database* c4db;   // Throws assertion-failure if null

@property (nonatomic, nullable) CBLC4Document* c4Doc;

@property (nonatomic, readonly) BOOL exists;

@property (nonatomic, readonly) NSString* revID;

@property (nonatomic, readonly) NSUInteger generation;

@property (nonatomic, readonly) id<CBLConflictResolver> effectiveConflictResolver;

@property (nonatomic, readonly, nullable) FLDict data;

- (instancetype) initWithDatabase: (nullable CBLDatabase*)database
                       documentID: (NSString*)documentID
                            c4Doc: (nullable CBLC4Document*)c4Doc
                       fleeceData: (nullable FLDict)data NS_DESIGNATED_INITIALIZER;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (BOOL) selectConflictingRevision;
- (BOOL) selectCommonAncestorOfDoc: (CBLDocument*)doc1
                            andDoc: (CBLDocument*)doc2;

- (nullable NSData*) encode: (NSError**)outError;

@end

//////////////////

@interface CBLMutableDictionary ()

@property (readonly, nonatomic) BOOL changed;

@end

//////////////////

@interface CBLArray ()

- (instancetype) initEmpty;

@end

//////////////////

@interface CBLDictionary ()

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

@interface CBLMutableDocumentFragment ()

- (instancetype) initWithDocument: (CBLMutableDocument*)document;

@end

NS_ASSUME_NONNULL_END
