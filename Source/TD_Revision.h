//
//  TD_Revision.h
//  TouchDB
//
//  Created by Jens Alfke on 12/2/11.
//  Copyright (c) 2011 Couchbase, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
@class TD_Body;


/** Database sequence ID */
typedef SInt64 SequenceNumber;


/** Stores information about a revision -- its docID, revID, and whether it's deleted. It can also store the sequence number and document contents (they can be added after creation). */
@interface TD_Revision : NSObject
{
    @private
    NSString* _docID, *_revID;
    TD_Body* _body;
    SequenceNumber _sequence;
    bool _deleted;
    bool _missing;
}

- (id) initWithDocID: (NSString*)docID 
               revID: (NSString*)revID 
             deleted: (BOOL)deleted;
- (id) initWithBody: (TD_Body*)body;
- (id) initWithProperties: (NSDictionary*)properties;

+ (TD_Revision*) revisionWithProperties: (NSDictionary*)properties;

@property (readonly) NSString* docID;
@property (readonly) NSString* revID;
@property (readonly) bool deleted;
@property bool missing;

@property (strong) TD_Body* body;
@property (copy) NSDictionary* properties;
@property (copy) NSData* asJSON;

- (id) objectForKeyedSubscript: (NSString*)key;  // enables subscript access in Xcode 4.4+

@property SequenceNumber sequence;

- (NSComparisonResult) compareSequences: (TD_Revision*)rev;

/** Generation number: 1 for a new document, 2 for the 2nd revision, ...
    Extracted from the numeric prefix of the revID. */
@property (readonly) unsigned generation;

+ (unsigned) generationFromRevID: (NSString*)revID;

+ (BOOL) parseRevID: (NSString*)revID
     intoGeneration: (int*)outNum
          andSuffix: (NSString**)outSuffix;

- (TD_Revision*) copyWithDocID: (NSString*)docID revID: (NSString*)revID;

@end



/** An ordered list of TDRevs. */
@interface TD_RevisionList : NSObject <NSFastEnumeration>
{
    @private
    NSMutableArray* _revs;
}

- (id) init;
- (id) initWithArray: (NSArray*)revs;

@property (readonly) NSUInteger count;

- (TD_Revision*) revWithDocID: (NSString*)docID revID: (NSString*)revID;

- (NSEnumerator*) objectEnumerator;

@property (readonly) NSArray* allRevisions;
@property (readonly) NSArray* allDocIDs;
@property (readonly) NSArray* allRevIDs;

- (TD_Revision*) objectAtIndexedSubscript: (NSUInteger)index;  // enables subscript access in XC4.4+

- (void) addRev: (TD_Revision*)rev;
- (void) removeRev: (TD_Revision*)rev;

- (void) limit: (NSUInteger)limit;
- (void) sortBySequence;

@end


/** Compares revision IDs by CouchDB rules: generation number first, then the suffix. */
NSComparisonResult TDCompareRevIDs(NSString* revID1, NSString* revID2);

/** SQLite-compatible collation (comparison) function for revision IDs. */
int TDCollateRevIDs(void *context,
                    int len1, const void * chars1,
                    int len2, const void * chars2);
