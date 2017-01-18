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
#import "CBLBlob.h"
#include "c4BlobStore.h"

@class CBLBlobStore, CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLJSONCoding <NSObject>

@property (readonly, nonatomic) NSDictionary* jsonRepresentation;

@end

/// CBLDatabase:

@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) CBLBlobStore* blobStore;
@property (readonly, nonatomic) NSString* path;     // For unit tests

- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved;

@end

/// CBLProperties:

@interface CBLProperties ()

// Having changes flag
@property (nonatomic) BOOL hasChanges;

// Set the root or the original properties. After calling this method, the current changes will
// be on top of the new root properties and the hasChanges flag will be reset.
- (void) setRootDict: (nullable FLDict)root orProperties: (nullable NSDictionary*) props;

// Reset both current changes and hasChanges flag.
- (void) resetChanges;

- (FLSliceResult)encodeWith:(FLEncoder)encoder error:(NSError **)outError;

// Subclass should implement this to provide the sharedKeys.
- (FLSharedKeys) sharedKeys;

// Subclass should implement this to write binary files to disk
- (BOOL)storeBlob:(CBLBlob *)blob
            error:(NSError **)error;

// Subclass should implement this to read binary files to disk
- (nullable CBLBlob *)readBlobWithProperties:(NSDictionary *)properties
                                       error:(NSError **)error;

@end

/// CBLDocument:

@interface CBLDocument ()

- (instancetype) initWithDatabase: (CBLDatabase*)db
                            docID: (NSString*)docID
                        mustExist: (BOOL)mustExist
                            error: (NSError**)outError;

- (void)changedExternally;
@end

// CBLBlob:

@interface CBLBlob () <CBLJSONCoding>

- (instancetype)initWithProperties:(NSDictionary *)properties
                        dataStream:(CBLBlobStream *)stream
                             error:(NSError **)outError;

- (BOOL)install:(C4BlobStore *)store error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
