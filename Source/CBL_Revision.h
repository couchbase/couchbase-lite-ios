//
//  CBL_Revision.h
//  CouchbaseLite
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CBLDatabase.h"
@class CBL_Body, CBL_MutableRevision;


/** Database sequence ID */
typedef SInt64 SequenceNumber;


/** Stores information about a revision -- its docID, revID, and whether it's deleted. It can also store the sequence number and document contents (they can be added after creation). */
@interface CBL_Revision : NSObject <NSMutableCopying>

- (instancetype) initWithDocID: (NSString*)docID
                         revID: (NSString*)revID
                       deleted: (BOOL)deleted;
- (instancetype) initWithBody: (CBL_Body*)body;
- (instancetype) initWithProperties: (NSDictionary*)properties;

+ (instancetype) revisionWithProperties: (NSDictionary*)properties;

@property (readonly) NSString* docID;
@property (readonly) NSString* revID;
@property (readonly) bool deleted;
@property (readonly) bool missing;

@property (readonly,strong) CBL_Body* body;
@property (readonly,copy) NSDictionary* properties;
@property (readonly,copy) NSData* asJSON;

- (id) objectForKeyedSubscript: (NSString*)key;  // enables subscript access in Xcode 4.4+

/** Revision's sequence number, or 0 if unknown.
    This property is settable, but only once. That is, it starts out zero and can be
    set to the correct value, but after that it becomes immutable. */
@property SequenceNumber sequence;

- (NSComparisonResult) compareSequences: (CBL_Revision*)rev;

/** Generation number: 1 for a new document, 2 for the 2nd revision, ...
    Extracted from the numeric prefix of the revID. */
@property (readonly) unsigned generation;

+ (unsigned) generationFromRevID: (NSString*)revID;

+ (BOOL) parseRevID: (NSString*)revID
     intoGeneration: (int*)outNum
          andSuffix: (NSString**)outSuffix;

- (CBL_MutableRevision*) mutableCopyWithDocID: (NSString*)docID revID: (NSString*)revID;

@end



@interface CBL_MutableRevision : CBL_Revision

@property (readwrite, strong) CBL_Body* body;
@property (readwrite, copy) NSDictionary* properties;
@property (readwrite, copy) NSData* asJSON;
@property (readwrite) bool missing;

@end



/** An ordered list of CBLRevs. */
@interface CBL_RevisionList : NSObject <NSFastEnumeration>
{
    @private
    NSMutableArray* _revs;
}

- (instancetype) init;
- (instancetype) initWithArray: (NSArray*)revs;

@property (readonly) NSUInteger count;

- (CBL_Revision*) revWithDocID: (NSString*)docID revID: (NSString*)revID;

- (NSEnumerator*) objectEnumerator;

@property (readonly) NSArray* allRevisions;
@property (readonly) NSArray* allDocIDs;
@property (readonly) NSArray* allRevIDs;

- (CBL_Revision*) objectAtIndexedSubscript: (NSUInteger)index;  // enables subscript access in XC4.4+

- (void) addRev: (CBL_Revision*)rev;
- (void) removeRev: (CBL_Revision*)rev;

- (void) limit: (NSUInteger)limit;
- (void) sortBySequence;

@end


/** Compares revision IDs by CouchDB rules: generation number first, then the suffix. */
NSComparisonResult CBLCompareRevIDs(NSString* revID1, NSString* revID2);

/** SQLite-compatible collation (comparison) function for revision IDs. */
int CBLCollateRevIDs(void *context,
                    int len1, const void * chars1,
                    int len2, const void * chars2);
