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
#import "CBLBlob.h"
#import "CBLDatabase.h"
#import "CBLDocument.h"
#import "CBLSubdocument.h"

struct c4BlobStore;

#ifdef __cplusplus
namespace cbl {
    class SharedKeys;
}
#endif

@class CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN


@protocol CBLJSONCoding <NSObject>

@property (readonly, nonatomic) NSDictionary* jsonRepresentation;

@end


/// CBLDatabase:


@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;

#ifdef __cplusplus
@property (readonly, nonatomic) cbl::SharedKeys sharedKeys;
#endif

- (void) document: (CBLDocument*)doc hasUnsavedChanges: (bool)unsaved;

- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;

@end


/// CBLProperties:


@interface CBLProperties ()

#ifdef __cplusplus
- (instancetype) initWithSharedKeys: (cbl::SharedKeys)sharedKeys;
@property (nonatomic) cbl::SharedKeys* sharedKeys;
#endif

// Having changes flag
@property (nonatomic) BOOL hasChanges;

// Called after a change occurs
- (void) markChangedKey: (NSString*)key;

// Reset all changes keys and mark hasChanges status to NO:
- (void) resetChangesKeys;

// Set the root properties. After calling this method, the current changes will
// be on top of the new root properties and the hasChanges flag will be reset.
- (void) setRootDict: (nullable FLDict)root;

// Update all subdocuments in properties with the new FLDict values from the new root, and
// invalidate all obsolete subdocuments. This method is called after the document is saved.
- (void) useNewRoot;

// Check whether the properties has the root properties set or not.
- (BOOL) hasRoot;

// Encode the current properties into a fleece object.
- (FLSliceResult)encodeWith:(FLEncoder)encoder error:(NSError **)outError;

// The current saved properties.
- (nullable NSDictionary *)savedProperties;

// Subclass should implement this to write binary files to disk
- (BOOL)storeBlob:(CBLBlob *)blob
            error:(NSError **)error;

// Subclass should implement this to read binary files to disk
- (nullable CBLBlob *)blobWithProperties:(NSDictionary *)properties error:(NSError **)error;

@end


// CBLBlob:


@interface CBLBlob () <CBLJSONCoding>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties
                            error: (NSError**)outError;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


NS_ASSUME_NONNULL_END
