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
#import "CBLDatabaseConfiguration.h"
#import "CBLDatabaseChange.h"
#import "CBLMutableDocument.h"
#import "CBLDocumentChange.h"
#import "CBLJSONCoding.h"
#import "CBLReplicator.h"
#import "CBLLiveQuery.h"


struct c4BlobStore;

@class CBLBlobStream;

NS_ASSUME_NONNULL_BEGIN


/// CBLDatabase:


@interface CBLDatabase ()

@property (readonly, nonatomic, nullable) C4Database* c4db;
@property (readonly, nonatomic) dispatch_queue_t dispatchQueue;
@property (readonly, nonatomic) NSMapTable<NSURL*,CBLReplicator*>* replications;
@property (readonly, nonatomic) NSMutableSet<CBLReplicator*>* activeReplications;
@property (readonly, nonatomic) NSMutableSet<CBLLiveQuery*>* liveQueries;
@property (readonly, nonatomic) FLSharedKeys sharedKeys;

- (nullable struct c4BlobStore*) getBlobStore: (NSError**)outError;
- (bool) resolveConflictInDocument: (NSString*)docID
                     usingResolver: (id<CBLConflictResolver>)resolver
                             error: (NSError**)outError;

@end


/// CBLDatabaseConfigurationBuilder:


@interface CBLDatabaseConfigurationBuilder ()

+ (NSString*) defaultDirectory;

@end


// CBLBlob:


@interface CBLBlob () <CBLJSONCoding>

- (instancetype) initWithDatabase: (CBLDatabase*)db
                       properties: (NSDictionary *)properties;

- (BOOL)installInDatabase: (CBLDatabase *)db error:(NSError **)error;

@end


// CBLConflict:

@interface CBLConflict ()

- (instancetype) initWithMine: (CBLDocument*)mine
                       theirs: (CBLDocument*)theirs
                         base: (nullable CBLDocument*)base;

@end


// CBLDefaultConflictResolver:


@interface CBLDefaultConflictResolver : NSObject <CBLConflictResolver>
@end


// CBLDocumentChange:

@interface CBLDocumentChange ()

- (instancetype) initWithDatabase: (CBLDatabase*)database
                       documentID: (NSString*)documentID;

@end


// CBLDatabaseChange:

@interface CBLDatabaseChange ()

/** check whether the changes are from the current database object or not. */
@property (readonly, nonatomic) BOOL isExternal;

- (instancetype) initWithDatabase: (CBLDatabase*)database
                      documentIDs: (NSArray*)documentIDs
                       isExternal: (BOOL)isExternal;

@end


NS_ASSUME_NONNULL_END
