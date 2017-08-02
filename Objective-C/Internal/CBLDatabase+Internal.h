//
//  CBLDatabase+Internal.h
//  CouchbaseLite
//
//  Created by Pasin Suriyentrakorn on 1/3/17.
//  Copyright © 2017 Couchbase. All rights reserved.
//

#pragma once
#import "c4.h"
#import "Fleece.h"
#import "CBLBlob.h"
#import "CBLConflictResolver.h"
#import "CBLDatabase.h"
#import "CBLDatabaseChange.h"
#import "CBLDocument.h"
#import "CBLDocumentChange.h"
#import "CBLJSONCoding.h"


struct c4BlobStore;

#ifdef __cplusplus
namespace cbl {
    class SharedKeys;
}
#endif

@class CBLBlobStream;
@class CBLReplicator;

NS_ASSUME_NONNULL_BEGIN


/// CBLDatabase:


@interface CBLDatabase ()

@property (atomic, readonly, nullable) C4Database* c4db;
@property (atomic, readonly) NSMapTable<NSURL*,CBLReplicator*>* replications;
@property (atomic, readonly) NSMutableSet* activeReplications;

#ifdef __cplusplus
@property (atomic, readonly) cbl::SharedKeys sharedKeys;
#endif

- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;
- (bool) resolveConflictInDocument: (NSString*)docID
                     usingResolver: (nullable id<CBLConflictResolver>)resolver
                             error: (NSError**)outError;

@end


// CBLBlob:


@interface CBLBlob () <CBLJSONCoding>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


// CBLConflict:

@interface CBLConflict ()

- (instancetype) initWithMine: (CBLReadOnlyDocument*)mine
                       theirs: (CBLReadOnlyDocument*)theirs
                         base: (nullable CBLReadOnlyDocument*)base;

@end


// CBLDefaultConflictResolver:


@interface CBLDefaultConflictResolver : NSObject <CBLConflictResolver>
@end


// CBLDocumentChange:

@interface CBLDocumentChange ()

- (instancetype) initWithDocumentID: (NSString*)documentID;

@end


// CBLDatabaseChange:

@interface CBLDatabaseChange ()

- (instancetype) initWithDocumentIDs: (NSArray*)documentIDs isExternal: (BOOL)isExternal;

@end


NS_ASSUME_NONNULL_END
