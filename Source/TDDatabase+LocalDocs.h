//
//  TDDatabase+LocalDocs.h
//  TouchDB
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>


@interface TDDatabase (LocalDocs)

- (TDRevision*) getLocalDocumentWithID: (NSString*)docID 
                            revisionID: (NSString*)revID;

- (TDRevision*) putLocalRevision: (TDRevision*)revision
                  prevRevisionID: (NSString*)prevRevID
                          status: (TDStatus*)outStatus;

- (TDStatus) deleteLocalDocumentWithID: (NSString*)docID
                            revisionID: (NSString*)revID;

@end
