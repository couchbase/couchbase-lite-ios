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

/** Stores a new (or initial) revision of a document. This is what's invoked by a PUT or POST. As with those, the previous revision ID must be supplied when necessary and the call will fail if it doesn't match.
    @param inDocID  The document ID. If nil, a new UUID will be assigned.
    @param properties  The new revision's properties.
    @param inPrevRevID  The ID of the revision to replace (same as the "?rev=" parameter to a PUT), or nil if this is a new document.
    @param allowConflict  If NO, an error status kCBLStatusConflict will be returned if the insertion would create a conflict, i.e. if the previous revision already has a child.
    @param outStatus  On return, an HTTP status code indicating success or failure.
    @param outError  On return, an error indicating a reason of the failure.
    @return  A new CBL_Revision with the docID, revID and sequence filled in (but no body). */
- (CBL_Revision*) putDocID: (NSString*)inDocID
                properties: (NSMutableDictionary*)properties
            prevRevisionID: (CBL_RevID*)inPrevRevID
             allowConflict: (BOOL)allowConflict
                    source: (NSURL*)source
                    status: (CBLStatus*)outStatus
                     error: (NSError**)outError;

/** Inserts an already-existing revision replicated from a remote database. It must already have a revision ID. This may create a conflict! The revision's history must be given; ancestor revision IDs that don't already exist locally will create phantom revisions with no content. */
- (CBLStatus) forceInsert: (CBL_Revision*)rev
          revisionHistory: (NSArray<CBL_RevID*>*)history
                   source: (NSURL*)source
                    error: (NSError**)outError;

/** Parses the _revisions dict from a document into an array of revision ID strings */
+ (NSArray<CBL_RevID*>*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties;


#if DEBUG // for testing only
- (CBL_Revision*) putRevision: (CBL_MutableRevision*)revision
               prevRevisionID: (CBL_RevID*)prevRevID
                allowConflict: (BOOL)allowConflict
                       status: (CBLStatus*)outStatus
                        error: (NSError**)outError;
#endif

@end
