//
//  CBL_Revision.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011-2013 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"
#import "CBL_Body.h"
#import "CBL_RevID.h"
#import "CBLMisc.h"
@class CBL_MutableRevision;


/** Stores information about a revision -- its docID, revID, and whether it's deleted. It can also store the sequence number and document contents (they can be added after creation). */
@interface CBL_Revision : NSObject <NSMutableCopying>

- (instancetype) initWithDocID: (NSString*)docID
                         revID: (CBL_RevID*)revID
                       deleted: (BOOL)deleted;
- (instancetype) initWithDocID: (NSString*)docID
                         revID: (CBL_RevID*)revID
                       deleted: (BOOL)deleted
                          body: (CBL_Body*)body;
- (instancetype) initWithBody: (CBL_Body*)body;
- (instancetype) initWithProperties: (NSDictionary*)properties;

+ (instancetype) revisionWithProperties: (NSDictionary*)properties;

@property (readonly) NSString* docID;
@property (readonly) CBL_RevID* revID;
@property (readonly) NSString* revIDString;
@property (readonly) bool deleted;
@property (readonly) bool missing;

@property (readonly,strong) CBL_Body* body;
@property (readonly,copy) NSDictionary* properties;
@property (readonly,copy) NSData* asJSON;

/** Adds "_id", "_rev", "_deleted" properties */
- (CBL_Revision*) revisionByAddingBasicMetadata;

- (CBL_Revision*) copyWithoutBody;

/** Returns the JSON to be stored into the database.
    This has all the special keys like "_id" stripped out, and keys in canonical order. */
@property (readonly) NSData* asCanonicalJSON;

+ (NSData*) asCanonicalJSON: (NSDictionary*)properties
                      error: (NSError**)error;

- (id) objectForKeyedSubscript: (NSString*)key;  // enables subscript access in Xcode 4.4+

/** Returns the "_attachments" property, validating that it's a dictionary. */
@property (readonly) NSDictionary* attachments;

/** Revision's sequence number. If sequence is unknown/unset, throws an exception.
    This property is settable, but only once. That is, it starts out zero and can be
    set to the correct value, but after that it becomes immutable. */
@property SequenceNumber sequence;

/** Revision's sequence number, or 0 if unknown/unset. */
@property (readonly) SequenceNumber sequenceIfKnown;

- (void) forgetSequence;

- (NSComparisonResult) compareSequences: (CBL_Revision*)rev;

- (NSComparisonResult) compareSequencesDescending: (CBL_Revision*)rev;

/** Generation number: 1 for a new document, 2 for the 2nd revision, ...
    Extracted from the numeric prefix of the revID. */
@property (readonly) unsigned generation;

- (CBL_MutableRevision*) mutableCopyWithDocID: (NSString*)docID revID: (CBL_RevID*)revID;

@end



@interface CBL_MutableRevision : CBL_Revision

@property (readwrite, strong) CBL_Body* body;
@property (readwrite, copy) NSDictionary* properties;
@property (readwrite) bool missing;

/** Overridden to make this settable. When set, the "_id", "_rev" and "_deleted" properties will be
    added to the JSON data; it MUST NOT already include them! */
@property (readwrite, copy) NSData* asJSON;

- (void) setDocID:(NSString *)docID
            revID: (CBL_RevID*)revID;

- (void) setObject: (id)object forKeyedSubscript: (NSString*)key;  // subscript access in Xcode 4.4+

/** Calls the block on every attachment dictionary. The block can return a different dictionary,
    which will be replaced in the rev's properties. If it returns nil, the operation aborts.
    Returns YES if any changes were made. */
- (BOOL) mutateAttachments: (NSDictionary*(^)(NSString*, NSDictionary*))block;

@end



/** An ordered list of CBLRevs. */
@interface CBL_RevisionList : NSObject <NSFastEnumeration, NSMutableCopying>

- (instancetype) init;
- (instancetype) initWithArray: (NSArray*)revs;

@property (readonly) NSUInteger count;

- (CBL_Revision*) revWithDocID: (NSString*)docID;
- (CBL_Revision*) revWithDocID: (NSString*)docID revID: (CBL_RevID*)revID;

- (NSEnumerator*) objectEnumerator;

@property (readonly) NSArray* allRevisions;
@property (readonly) NSArray* allDocIDs;
@property (readonly) NSArray* allRevIDs;

- (CBL_Revision*) objectAtIndexedSubscript: (NSUInteger)index;  // enables subscript access in XC4.4+

- (void) addRev: (CBL_Revision*)rev;
- (void) removeRev: (CBL_Revision*)rev;
- (void) removeRevIdenticalTo: (CBL_Revision*)rev;
- (CBL_Revision*) removeAndReturnRev: (CBL_Revision*)rev;  // returns the object removed, or nil
- (void) removeObjectAtIndex: (NSUInteger)index;

- (void) limit: (NSUInteger)limit;
- (void) sortBySequenceAscending:(BOOL)ascending;
- (void) sortByDocID;

@end


/** A block that can filter revisions by passing or rejecting them. */
typedef BOOL (^CBL_RevisionFilter)(CBL_Revision*);
