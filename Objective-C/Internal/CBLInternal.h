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
#import "CBLConflictResolver.h"
#import "CBLDatabase.h"
#import "CBLDocument.h"
#import "CBLJSONCoding.h"
#import "CBLSubdocument.h"


struct c4BlobStore;

#ifdef __cplusplus
namespace cbl {
    class SharedKeys;
}
#endif

@class CBLBlobStream;
@class CBLReplication;

NS_ASSUME_NONNULL_BEGIN


/// CBLDatabase:


@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;

@property (readonly, nonatomic) NSUInteger documentCount; // For unit tests

@property (readonly, nonatomic) NSMapTable<NSURL*,CBLReplication*>* replications;
@property (readonly, nonatomic) NSMutableSet* activeReplications;

#ifdef __cplusplus
@property (readonly, nonatomic) cbl::SharedKeys sharedKeys;
#endif

- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;

@end


// CBLBlob:


@interface CBLBlob () <CBLJSONCoding>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


// CBLConflict:

@interface CBLConflict ()

- (instancetype) initWithSource: (CBLReadOnlyDocument*)source
                         target: (CBLReadOnlyDocument*)target
                 commonAncestor: (nullable CBLReadOnlyDocument*)commonAncestor
                  operationType: (CBLOperationType)operationType;

@end


NS_ASSUME_NONNULL_END
