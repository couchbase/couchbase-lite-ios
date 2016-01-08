//
//  CBLForestBridge.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/1/14.
//  Copyright (c) 2014-2015 Couchbase, Inc. All rights reserved.
//

extern "C" {
#import "c4Database.h"
#import "c4Document.h"
#import "CBL_Storage.h"
}
@class CBLSymmetricKey;


static inline C4Slice dataToSlice(UU NSData* data) {
    return {data.bytes, data.length};
}

static inline C4Slice stringToSlice(UU NSString* str) {
    return dataToSlice([str dataUsingEncoding: NSUTF8StringEncoding]);
}

NSString* C4SliceToString(C4Slice s);
NSData* C4SliceToData(C4Slice s);

CBLStatus CBLStatusFromC4Error(C4Error);

BOOL ErrorFromC4Error(C4Error, NSError**);


@interface CBLForestBridge : NSObject

+ (void) setEncryptionKey: (C4EncryptionKey*)fdbKey
         fromSymmetricKey: (CBLSymmetricKey*)key;

+ (C4Database*) openDatabaseAtPath: (NSString*)path
                         withFlags: (C4DatabaseFlags)flags
                     encryptionKey: (CBLSymmetricKey*)key
                             error: (NSError**)outError;

+ (CBL_MutableRevision*) revisionObjectFromForestDoc: (C4Document*)doc
                                               docID: (NSString*)docID
                                               revID: (NSString*)revID
                                            withBody: (BOOL)withBody
                                              status: (CBLStatus*)outStatus;

+ (NSMutableDictionary*) bodyOfSelectedRevision: (C4Document*)doc;

+ (CBL_MutableRevision*) revisionObjectFromC4Doc: (C4Document*)doc
                                           revID: (NSString*)revID
                                        withBody: (BOOL)withBody;

/** Stores the body of a revision (including metadata) into a CBL_MutableRevision. */
+ (CBLStatus) loadBodyOfRevisionObject: (CBL_MutableRevision*)rev
                  fromSelectedRevision: (C4Document*)doc;

@end
