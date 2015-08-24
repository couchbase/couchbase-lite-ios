//
//  CBL_BlobStore+Internal.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/23/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_BlobStore.h"


// Name of file in blob-store dir that records encryption type used (currently "AES")
#define kEncryptionMarkerFilename @"_encryption"


@interface CBL_BlobStore ()

- (NSString*) rawPathForKey: (CBLBlobKey)key;
@property (readonly, nonatomic) NSString* tempDir;
@property (readonly) CBLSymmetricKey* encryptionKey;

#if DEBUG
- (BOOL) markEncrypted: (BOOL)encrypted error: (NSError**)outError; // exposed for testing ONLY
#endif
@end
