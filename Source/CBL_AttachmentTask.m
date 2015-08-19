//
//  CBL_AttachmentTask.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/15.
//  Copyright © 2015 Couchbase, Inc. All rights reserved.
//

#import "CBL_AttachmentTask.h"
#import "CBL_Replicator.h"
#import "CBL_BlobStoreWriter.h"
#import "CBLProgressGroup.h"
#import "MYBlockUtils.h"


#define kProgressInterval 0.25


@implementation CBL_AttachmentID

@synthesize docID=_docID, revID=_revID, name=_name, metadata=_metadata;

- (instancetype) initWithDocID: (NSString*)docID
                         revID: (NSString *)revID
                          name: (NSString*)attachmentName
                      metadata: (NSDictionary*)metadata
{
    self = [super init];
    if (self) {
        _docID = [docID copy];
        _revID = [revID copy];
        _name = [attachmentName copy];
        _metadata = [metadata copy];
    }
    return self;
}

- (instancetype) copyWithZone: (NSZone*)zone {
    return self;
}

- (NSUInteger) hash {
    return _docID.hash ^ _revID.hash ^ _name.hash;
}

- (BOOL) isEqual: (id)object {
    return [object isKindOfClass: [CBL_AttachmentID class]]
        && $equal(_docID, [object docID])
        && $equal(_revID, [object revID])
        && $equal(_name,  [object name]);
}

- (NSString*) description {
    return $sprintf(@"%@[%@/%@ rev=%@]", [self class], _docID, _name, _revID);
}

@end



@implementation CBL_AttachmentTask
{
    CBL_BlobStoreWriter* _writer;
    CBLProgressGroup* _progress;
}

- (instancetype) initWithID: (CBL_AttachmentID*)ID
                   progress: (NSProgress*)progress
{
    self = [super init];
    if (self) {
        _ID = ID;
        _progress = [CBLProgressGroup new];
        if (_progress)
            [_progress addProgress: progress];
    }
    return self;
}

@synthesize ID=_ID, progress=_progress;

- (void) setWriter:(CBL_BlobStoreWriter *)writer {
    _writer = writer;
    _writer.progress = _progress;
}

- (CBL_BlobStoreWriter *)writer {
    return _writer;
}

@end