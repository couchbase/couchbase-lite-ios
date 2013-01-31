//
//  CBL_Database+Insertion.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import "CBL_Database.h"
#import "CBLDatabase.h"
@protocol CBL_ValidationContext;


/** Validation block, used to approve revisions being added to the database. */
typedef BOOL (^CBL_ValidationBlock) (CBL_Revision* newRevision,
                                   id<CBL_ValidationContext> context);


@interface CBL_Database (Insertion)

+ (BOOL) isValidDocumentID: (NSString*)str;

+ (NSString*) generateDocumentID;

/** Stores a new (or initial) revision of a document. This is what's invoked by a PUT or POST. As with those, the previous revision ID must be supplied when necessary and the call will fail if it doesn't match.
    @param revision  The revision to add. If the docID is nil, a new UUID will be assigned. Its revID must be nil. It must have a JSON body.
    @param prevRevID  The ID of the revision to replace (same as the "?rev=" parameter to a PUT), or nil if this is a new document.
    @param allowConflict  If NO, an error status kCBLStatusConflict will be returned if the insertion would create a conflict, i.e. if the previous revision already has a child.
    @param outStatus  On return, an HTTP status code indicating success or failure.
    @return  A new CBL_Revision with the docID, revID and sequence filled in (but no body). */
- (CBL_Revision*) putRevision: (CBL_Revision*)revision
             prevRevisionID: (NSString*)prevRevID
              allowConflict: (BOOL)allowConflict
                     status: (CBLStatus*)outStatus;

/** Inserts an already-existing revision replicated from a remote database. It must already have a revision ID. This may create a conflict! The revision's history must be given; ancestor revision IDs that don't already exist locally will create phantom revisions with no content. */
- (CBLStatus) forceInsert: (CBL_Revision*)rev
         revisionHistory: (NSArray*)history
                  source: (NSURL*)source;

/** Parses the _revisions dict from a document into an array of revision ID strings */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties;

/** Define or clear a named document validation function.  */
- (void) defineValidation: (NSString*)validationName asBlock: (CBL_ValidationBlock)validationBlock;
- (CBL_ValidationBlock) validationNamed: (NSString*)validationName;

/** Compacts the database storage by removing the bodies and attachments of obsolete revisions. */
- (CBLStatus) compact;

/** Purges specific revisions, which deletes them completely from the local database _without_ adding a "tombstone" revision. It's as though they were never there.
    @param docsToRevs  A dictionary mapping document IDs to arrays of revision IDs.
    @param outResult  On success will point to an NSDictionary with the same form as docsToRev, containing the doc/revision IDs that were actually removed. */
- (CBLStatus) purgeRevisions: (NSDictionary*)docsToRevs
                     result: (NSDictionary**)outResult;

@end



@protocol CBL_ValidationContext <CBLValidationContext>
@property (readonly) CBL_Revision* current_Revision;
@end
