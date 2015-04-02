//
//  CBLDatabase+Insertion.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//

#import "CBLDatabase+Internal.h"
#import "CBLDatabase.h"


@interface CBLDatabase (Insertion)

+ (BOOL) isValidDocumentID: (NSString*)str;

+ (NSString*) generateDocumentID;

- (NSString*) _generateRevIDForJSON: (NSData*)json
                            deleted: (BOOL)deleted
                          prevRevID: (NSString*) prev;

- (CBL_Revision*) putDocID: (NSString*)inDocID
                properties: (NSMutableDictionary*)properties
            prevRevisionID: (NSString*)inPrevRevID
             allowConflict: (BOOL)allowConflict
                    status: (CBLStatus*)outStatus
                     error: (NSError**)outError;

/** Stores a new (or initial) revision of a document. This is what's invoked by a PUT or POST. As with those, the previous revision ID must be supplied when necessary and the call will fail if it doesn't match.
    @param revision  The revision to add. If the docID is nil, a new UUID will be assigned. Its revID must be nil. It must have a JSON body.
    @param prevRevID  The ID of the revision to replace (same as the "?rev=" parameter to a PUT), or nil if this is a new document.
    @param allowConflict  If NO, an error status kCBLStatusConflict will be returned if the insertion would create a conflict, i.e. if the previous revision already has a child.
    @param outStatus  On return, an HTTP status code indicating success or failure.
    @return  A new CBL_Revision with the docID, revID and sequence filled in (but no body). */
- (CBL_Revision*) putRevision: (CBL_MutableRevision*)revision
               prevRevisionID: (NSString*)prevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
                        error: (NSError**)outError;

/** Inserts an already-existing revision replicated from a remote database. It must already have a revision ID. This may create a conflict! The revision's history must be given; ancestor revision IDs that don't already exist locally will create phantom revisions with no content. */
- (CBLStatus) forceInsert: (CBL_Revision*)rev
          revisionHistory: (NSArray*)history
                   source: (NSURL*)source
                    error: (NSError**)outError;

/** Parses the _revisions dict from a document into an array of revision ID strings */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties;

@end
