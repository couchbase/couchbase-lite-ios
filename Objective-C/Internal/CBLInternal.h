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

struct c4BlobStore;

@class CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN

@protocol CBLJSONCoding <NSObject>

@property (readonly, nonatomic) NSDictionary* jsonRepresentation;

@end

/// CBLDatabase:

@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) NSString* path;     // For unit tests

- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved;

- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;

@end

/// CBLProperties:

@interface CBLProperties ()

// Having changes flag
@property (nonatomic) BOOL hasChanges;

// Set the root properties. After calling this method, the current changes will
// be on top of the new root properties and the hasChanges flag will be reset.
- (void) setRootDict: (nullable FLDict)root;

// Reset both current changes and hasChanges flag.
- (void) resetChanges;

- (FLSliceResult)encodeWith:(FLEncoder)encoder error:(NSError **)outError;

// Subclass should implement this to provide the sharedKeys.
- (FLSharedKeys) sharedKeys;

- (nullable NSDictionary *)savedProperties;

// Subclass should implement this to write binary files to disk
- (BOOL)storeBlob:(CBLBlob *)blob
            error:(NSError **)error;

// Subclass should implement this to read binary files to disk
- (nullable CBLBlob *)blobWithProperties:(NSDictionary *)properties error:(NSError **)error;

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

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties
                            error: (NSError**)outError;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
