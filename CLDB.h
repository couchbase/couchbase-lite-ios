/*
 *  CLDB.h
 *  ToyCouch
 *
 *  Created by Jens Alfke on 6/19/10.
 *  Copyright 2010 Jens Alfke. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>
@class FMDatabase, CLDocument;


/** A ToyCouch database. Acts primarily as a container for named tables (CLCaches). */
@interface CLDB : NSObject
{
    FMDatabase *_fmdb;
    NSInteger _transactionLevel;
    BOOL _transactionFailed;
}    
        
- (id) initWithPath: (NSString*)path;
- (BOOL) open;
#if SQLITE_VERSION_NUMBER >= 3005000
- (BOOL) openWithFlags:(int)flags;
#endif
- (BOOL) close;

@property (readonly) NSString* path;
@property (readonly) NSString* name;
@property (readonly) int error;

- (void) beginTransaction;
- (void) endTransaction;
@property BOOL transactionFailed;

- (int) compact;

// DOCUMENTS:

- (CLDocument*) getDocumentWithID: (NSString*)docID;
- (CLDocument*) getDocumentWithID: (NSString*)docID revisionID: (NSString*)revID;

- (CLDocument*) putDocument: (CLDocument*)document
                     withID: (NSString*)docID 
                 revisionID: (NSString*)revID
                     status: (int*)outStatus;
- (CLDocument*) createDocument: (CLDocument*)document
                        status: (int*)outStatus;
- (int) deleteDocumentWithID: (NSString*)docID 
                  revisionID: (NSString*)revID;

@end
