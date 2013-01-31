//
//  CBL_Pusher.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/5/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import "CBL_Puller.h"
#import "CBL_Database.h"


/** Replicator that pushes to a remote CouchDB. */
@interface CBL_Pusher : CBL_Replicator
{
    BOOL _createTarget;
    BOOL _creatingTarget;
    BOOL _observing;
    BOOL _uploading;
    NSMutableArray* _uploaderQueue;
    BOOL _dontSendMultipart;
}

@property BOOL createTarget;

@end
