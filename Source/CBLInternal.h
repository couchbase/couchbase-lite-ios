//
//  CBLInternal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/8/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase.h"
#import "CBLDatabase+Attachments.h"
#import "CBLDatabaseChange.h"
#import "CBLManager+Internal.h"
#import "CBLView+Internal.h"
#import "CBL_Server.h"
#import "CBL_BlobStore.h"
@class CBL_Attachment, CBL_BlobStoreWriter, CBLDatabaseChange;


// In a method/function implementation (not declaration), declaring an object parameter as
// __unsafe_unretained avoids the implicit retain at the start of the function and releasse at
// the end. In a performance-sensitive function, those can be significant overhead. Of course this
// should never be used if the object might be released during the function.
#define UU __unsafe_unretained


@interface CBLDatabase (Insertion_Internal)
- (CBLStatus) validateRevision: (CBL_Revision*)newRev previousRevision: (CBL_Revision*)oldRev;
@end

@interface CBLDatabase (Attachments_Internal)
- (void) rememberAttachmentWriter: (CBL_BlobStoreWriter*)writer;
- (void) rememberAttachmentWritersForDigests: (NSDictionary*)writersByDigests;
#if DEBUG
- (id) attachmentWriterForAttachment: (NSDictionary*)attachment;
#endif
@end

@interface CBLDatabase (Replication_Internal)
- (void) stopAndForgetReplicator: (id<CBL_Replicator>)repl;
- (NSString*) lastSequenceWithCheckpointID: (NSString*)checkpointID;
- (BOOL) setLastSequence: (NSString*)lastSequence withCheckpointID: (NSString*)checkpointID;
@end


@interface CBL_Server ()
#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end


@interface CBLManager (Testing)
#if DEBUG
+ (instancetype) createEmptyAtPath: (NSString*)path;  // for testing
+ (instancetype) createEmptyAtTemporaryPath: (NSString*)name;  // for testing
#endif
@end
