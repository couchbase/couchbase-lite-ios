//
//  TD_Database+LocalDocs.h
//  TouchDB
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TD_Database.h>


@interface TD_Database (LocalDocs)

- (TD_Revision*) getLocalDocumentWithID: (NSString*)docID 
                            revisionID: (NSString*)revID;

- (TD_Revision*) putLocalRevision: (TD_Revision*)revision
                  prevRevisionID: (NSString*)prevRevID
                          status: (TDStatus*)outStatus;

- (TDStatus) deleteLocalDocumentWithID: (NSString*)docID
                            revisionID: (NSString*)revID;

@end
