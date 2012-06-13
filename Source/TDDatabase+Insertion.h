//
//  TDDatabase+Insertion.h
//  TouchDB
//
//  Created by Jens Alfke on 1/18/12.
//  Copyright (c) 2012 Couchbase, Inc. All rights reserved.
//

#import <TouchDB/TDDatabase.h>
@protocol TDValidationContext;


/** Validation block, used to approve revisions being added to the database. */
typedef BOOL (^TDValidationBlock) (TDRevision* newRevision,
                                   id<TDValidationContext> context);


@interface TDDatabase (Insertion)

+ (BOOL) isValidDocumentID: (NSString*)str;

+ (NSString*) generateDocumentID;

/** Stores a new (or initial) revision of a document. This is what's invoked by a PUT or POST. As with those, the previous revision ID must be supplied when necessary and the call will fail if it doesn't match.
    @param revision  The revision to add. If the docID is nil, a new UUID will be assigned. Its revID must be nil. It must have a JSON body.
    @param prevRevID  The ID of the revision to replace (same as the "?rev=" parameter to a PUT), or nil if this is a new document.
    @param allowConflict  If NO, an error status kTDStatusConflict will be returned if the insertion would create a conflict, i.e. if the previous revision already has a child.
    @param status  On return, an HTTP status code indicating success or failure.
    @return  A new TDRevision with the docID, revID and sequence filled in (but no body). */
- (TDRevision*) putRevision: (TDRevision*)revision
             prevRevisionID: (NSString*)prevRevID
              allowConflict: (BOOL)allowConflict
                     status: (TDStatus*)outStatus;

/** Inserts an already-existing revision replicated from a remote database. It must already have a revision ID. This may create a conflict! The revision's history must be given; ancestor revision IDs that don't already exist locally will create phantom revisions with no content. */
- (TDStatus) forceInsert: (TDRevision*)rev
         revisionHistory: (NSArray*)history
                  source: (NSURL*)source;

/** Parses the _revisions dict from a document into an array of revision ID strings */
+ (NSArray*) parseCouchDBRevisionHistory: (NSDictionary*)docProperties;

/** Define or clear a named document validation function.  */
- (void) defineValidation: (NSString*)validationName asBlock: (TDValidationBlock)validationBlock;
- (TDValidationBlock) validationNamed: (NSString*)validationName;

@end



typedef BOOL (^TDChangeEnumeratorBlock) (NSString* key, id oldValue, id newValue);


/** Context passed into a TDValidationBlock. */
@protocol TDValidationContext <NSObject>
/** The contents of the current revision of the document, or nil if this is a new document. */
@property (readonly) TDRevision* currentRevision;

/** The type of HTTP status to report, if the validate block returns NO.
    The default value is 403 ("Forbidden"). */
@property TDStatus errorType;

/** The error message to return in the HTTP response, if the validate block returns NO.
    The default value is "invalid document". */
@property (copy) NSString* errorMessage;

/** Returns an array of all the keys whose values are different between the current and new revisions. */
@property (readonly) NSArray* changedKeys;

/** Returns YES if only the keys given in the 'allowedKeys' array have changed; else returns NO and sets a default error message naming the offending key. */
- (BOOL) allowChangesOnlyTo: (NSArray*)allowedKeys;

/** Returns YES if none of the keys given in the 'disallowedKeys' array have changed; else returns NO and sets a default error message naming the offending key. */
- (BOOL) disallowChangesTo: (NSArray*)disallowedKeys;

/** Calls the 'enumerator' block for each key that's changed, passing both the old and new values.
    If the block returns NO, the enumeration stops and sets a default error message, and the method returns NO; else the method returns YES. */
- (BOOL) enumerateChanges: (TDChangeEnumeratorBlock)enumerator;

@end
