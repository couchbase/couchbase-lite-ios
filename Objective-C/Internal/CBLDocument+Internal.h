//
//  CBLDocumentObjectInternal.h
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
#import "CBLReadOnlySubdocument.h"
#import "CBLSubdocument.h"
#import "Fleece.h"


NS_ASSUME_NONNULL_BEGIN

@protocol CBLFleeceEncodable <NSObject>

- (BOOL) fleeceEncode: (FLEncoder)encoder
             database: (CBLDatabase*)database
                error: (NSError**)outError;

@end

//////////////////

@protocol CBLObjectChangeListener <NSObject>

- (void) objectDidChange: (id)object;

@end

//////////////////

@interface CBLDocument ()

@property (weak, nonatomic, nullable) id swiftDocument;

@property (nonatomic, nullable) CBLDatabase *database;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (BOOL) save: (NSError**)error;

- (BOOL) deleteDocument: (NSError**)error;

- (BOOL) purge: (NSError**)error;

@end

//////////////////

@interface CBLReadOnlyDocument ()

@property (nonatomic, nullable) CBLC4Document* c4Doc;

@property (nonatomic, readonly) BOOL exists;

@property (nonatomic, readonly) NSUInteger generation;

- (instancetype) initWithDocumentID: (NSString*)documentID
                              c4Doc: (nullable CBLC4Document*)c4Doc
                         fleeceData: (nullable CBLFLDict*)data;

@end

//////////////////

@interface CBLArray () <CBLObjectChangeListener>

- (void) addChangeListener: (id<CBLObjectChangeListener>)listener;

- (void) removeChangeListener: (id<CBLObjectChangeListener>)listener;

@end

@interface CBLBlob() <CBLFleeceEncodable>

@end

//////////////////

@interface CBLDictionary () <CBLObjectChangeListener>

@property (nonatomic) BOOL changed;

- (void) addChangeListener: (id<CBLObjectChangeListener>)listener;

- (void) removeChangeListener: (id<CBLObjectChangeListener>)listener;

@end

//////////////////

@interface CBLReadOnlyArray () <CBLFleeceEncodable>

@property (nonatomic, readonly, nullable) CBLFLArray* data;

- (instancetype) initWithFleeceData: (nullable CBLFLArray*)data;

@end

//////////////////

@interface CBLReadOnlyDictionary () <CBLFleeceEncodable>

@property (nonatomic, nullable) CBLFLDict* data;

@property (nonatomic, readonly) BOOL isEmpty;

- (instancetype) initWithFleeceData: (nullable CBLFLDict*)data;

@end

//////////////////

@interface CBLSubdocument ()

// @property (weak, nonatomic, nullable) id swiftSubdocument;

@property (readonly, nonatomic) CBLDictionary* dictionary;

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
