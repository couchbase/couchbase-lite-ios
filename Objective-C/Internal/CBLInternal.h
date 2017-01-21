//
//  CBLInternal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/3/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "c4.h"
#import "Fleece.h"
#import "CBLDatabase.h"
#import "CBLDocument.h"
#import "CBLSubdocument.h"

NS_ASSUME_NONNULL_BEGIN

/// CBLDatabase:

@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) NSString* path;     // For unit tests

- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved;

@end

/// JSONEncoding:

@protocol CBLJSONEncoding <NSObject>
- (id) encodeAsJSON;
@end

/// CBLProperties:

@interface CBLProperties () <CBLJSONEncoding>

// Having changes flag
@property (nonatomic) BOOL hasChanges;

// Shared keys
@property (readonly, nonatomic) FLSharedKeys sharedKeys;

// Fleece root
@property (nonatomic, nullable) FLDict root;


@end


/// CBLDocument:

@interface CBLDocument ()

- (instancetype) initWithDatabase: (CBLDatabase*)db
                            docID: (NSString*)docID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;
@end

/// CBLSubdocument:

typedef void (^CBLOnMutateBlock)();

@interface CBLSubdocument ()

@property (weak, nonatomic) id parent;

- (instancetype) initWithParent: (id)parent root: (nullable FLDict)rootDict;

- (void) setOnMutate: (nullable CBLOnMutateBlock)onMutate;

- (void) invalidate;

@end

NS_ASSUME_NONNULL_END
