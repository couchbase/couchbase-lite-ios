//
//  CBL_Database+LocalDocs.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/10/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBL_Database.h"


@interface CBL_Database (LocalDocs)

- (CBL_Revision*) getLocalDocumentWithID: (NSString*)docID 
                            revisionID: (NSString*)revID;

- (CBL_Revision*) putLocalRevision: (CBL_Revision*)revision
                  prevRevisionID: (NSString*)prevRevID
                          status: (CBLStatus*)outStatus;

- (CBLStatus) deleteLocalDocumentWithID: (NSString*)docID
                            revisionID: (NSString*)revID;

@end
