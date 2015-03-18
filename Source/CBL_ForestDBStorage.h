//
//  CBL_ForestDBStorage.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/14/15.
//  Copyright (c) 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_Storage.h"


@interface CBL_ForestDBStorage : NSObject <CBL_Storage>

@property (nonatomic, readonly) NSString* directory;
@property (nonatomic, readonly) void* forestDatabase; // really forestdb::Database*

/** Loads revision given its sequence. Assumes the given docID is valid. */
- (CBL_MutableRevision*) getDocumentWithID: (NSString*)docID
                                  sequence: (SequenceNumber)sequence
                                    status: (CBLStatus*)outStatus;

- (CBLStatus) _try: (CBLStatus(^)())block;

@end
