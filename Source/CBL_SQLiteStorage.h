//
//  CBL_SQLiteStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Storage.h"
@class CBL_FMDatabase;


@interface CBL_SQLiteStorage : NSObject <CBL_Storage>

@property (readonly, nonatomic) CBL_FMDatabase* fmdb;
@property (readonly, nonatomic) CBLStatus lastDbStatus;
@property (readonly, nonatomic) CBLStatus lastDbError;

- (void) optimizeSQLIndexes;

- (BOOL) runStatements: (NSString*)statements error: (NSError**)outError;

- (NSDictionary*) documentPropertiesFromJSON: (NSData*)json
                                       docID: (NSString*)docID
                                       revID: (NSString*)revID
                                     deleted: (BOOL)deleted
                                    sequence: (SequenceNumber)sequence
                                     options: (CBLContentOptions)options;

/** Loads revision given its sequence. Assumes the given docID is valid. */
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus;

@end


#if DEBUG
#define MOCK_ENCRYPTION
#endif

#ifdef MOCK_ENCRYPTION
// If this is YES, the storage acts as though encryption were supported, but doesn't actually
// encrypt anything. It just writes the encryption key to a file called "mock_key" in the
// database directory. Needless to say, this should only be used for testing!
extern BOOL CBLEnableMockEncryption;
#endif
