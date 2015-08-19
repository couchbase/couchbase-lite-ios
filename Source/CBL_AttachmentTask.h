//
//  CBL_AttachmentTask.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class CBL_BlobStoreWriter, CBLProgressGroup;


/** Simple value object representing a request for an attachment. Usable as an NSDictionary key. */
@interface CBL_AttachmentID : NSObject <NSCopying>
- (instancetype) initWithDocID: (NSString*)docID
                         revID: (NSString *)revID
                          name: (NSString*)attachmentName
                      metadata: (NSDictionary*)metadata;;
@property (readonly, nonatomic) NSString *docID, *revID, *name;
@property (readonly, nonatomic) NSDictionary* metadata;
@end



/** An asynchronous task to download an attachment. Keeps track of progress.
    Doesn't handle the actual networking; that's up to the replicator implementation. */
@interface CBL_AttachmentTask : NSObject

- (instancetype) initWithID: (CBL_AttachmentID*)ID
                   progress: (NSProgress*)progress;

@property (readonly, nonatomic) CBL_AttachmentID* ID;

@property (nonatomic) CBL_BlobStoreWriter* writer;

@property (readonly, nonatomic) CBLProgressGroup* progress;

@end
